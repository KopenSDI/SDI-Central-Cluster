package e2e

import (
	"context"
	"fmt"
	"strings"
	"time"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"

	opensdiv1alpha1 "male-policy-controller/api/v1alpha1"
	"male-policy-controller/test/utils"
)

var _ = Describe("MALE Controller E2E Tests", func() {
	const (
		timeout  = time.Second * 30
		interval = time.Second * 2
	)

	var (
		ctx       context.Context
		namespace string
		k8sClient client.Client
	)

	BeforeEach(func() {
		ctx = context.Background()
		namespace = "sdi-demo" // Use fixed namespace for testing

		// Initialize k8sClient from utils
		var err error
		k8sClient, err = utils.NewK8sClient()
		Expect(err).NotTo(HaveOccurred())

		// Ensure sdi-demo namespace exists
		ns := &corev1.Namespace{
			ObjectMeta: metav1.ObjectMeta{
				Name: namespace,
			},
		}
		err = k8sClient.Create(ctx, ns)
		// Ignore already exists error
		if err != nil && !strings.Contains(err.Error(), "already exists") {
			Expect(err).NotTo(HaveOccurred())
		}
	})

	AfterEach(func() {
		// 테스트 리소스 정리
		ns := &corev1.Namespace{
			ObjectMeta: metav1.ObjectMeta{
				Name: namespace,
			},
		}
		Expect(k8sClient.Delete(ctx, ns)).Should(Succeed())
	})

	Describe("Basic Policy Application", func() {
		It("should apply MALE policy to deployment with matching labels", func() {
			// 1. 테스트 워크로드 생성
			deployment := &appsv1.Deployment{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "test-ml-deployment",
					Namespace: namespace,
					Labels: map[string]string{
						"app":  "ml-service",
						"type": "inference",
						"env":  "test",
					},
				},
				Spec: appsv1.DeploymentSpec{
					Replicas: int32Ptr(1),
					Selector: &metav1.LabelSelector{
						MatchLabels: map[string]string{
							"app": "ml-service",
						},
					},
					Template: corev1.PodTemplateSpec{
						ObjectMeta: metav1.ObjectMeta{
							Labels: map[string]string{
								"app": "ml-service",
							},
						},
						Spec: corev1.PodSpec{
							Containers: []corev1.Container{
								{
									Name:  "ml-container",
									Image: "nginx:latest",
									Ports: []corev1.ContainerPort{
										{
											ContainerPort: 80,
										},
									},
								},
							},
						},
					},
				},
			}
			Expect(k8sClient.Create(ctx, deployment)).Should(Succeed())

			// 2. MALE 정책 생성
			policy := &opensdiv1alpha1.MALEPolicy{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "test-policy",
					Namespace: namespace,
				},
				Spec: opensdiv1alpha1.MALEPolicySpec{
					Accuracy: 800,
					Latency:  200,
					Energy:   600,
					Selector: map[string]string{
						"type": "inference",
						"env":  "test",
					},
					Description: "E2E test policy",
				},
			}
			Expect(k8sClient.Create(ctx, policy)).Should(Succeed())

			// 3. 정책이 적용되는지 확인
			Eventually(func() int32 {
				var updatedPolicy opensdiv1alpha1.MALEPolicy
				err := k8sClient.Get(ctx, types.NamespacedName{
					Name:      policy.Name,
					Namespace: namespace,
				}, &updatedPolicy)
				if err != nil {
					return 0
				}
				return updatedPolicy.Status.AppliedWorkloads
			}, timeout, interval).Should(Equal(int32(1)))

			// 4. Deployment에 MALE 어노테이션이 추가되었는지 확인
			Eventually(func() bool {
				var updatedDeployment appsv1.Deployment
				err := k8sClient.Get(ctx, types.NamespacedName{
					Name:      deployment.Name,
					Namespace: namespace,
				}, &updatedDeployment)
				if err != nil {
					return false
				}

				annotations := updatedDeployment.Annotations
				return annotations != nil &&
					annotations["male-policy.opensdi.io/accuracy"] == "800" &&
					annotations["male-policy.opensdi.io/latency"] == "200" &&
					annotations["male-policy.opensdi.io/energy"] == "600"
			}, timeout, interval).Should(BeTrue())

			// 5. Pod에 환경변수가 주입되었는지 확인
			Eventually(func() bool {
				var updatedDeployment appsv1.Deployment
				err := k8sClient.Get(ctx, types.NamespacedName{
					Name:      deployment.Name,
					Namespace: namespace,
				}, &updatedDeployment)
				if err != nil {
					return false
				}

				containers := updatedDeployment.Spec.Template.Spec.Containers
				if len(containers) == 0 {
					return false
				}

				envVars := containers[0].Env
				maleEnvs := map[string]string{}
				for _, env := range envVars {
					if env.Name == "MALE_ACCURACY" || env.Name == "MALE_LATENCY" || env.Name == "MALE_ENERGY" {
						maleEnvs[env.Name] = env.Value
					}
				}

				return len(maleEnvs) == 3 &&
					maleEnvs["MALE_ACCURACY"] == "800" &&
					maleEnvs["MALE_LATENCY"] == "200" &&
					maleEnvs["MALE_ENERGY"] == "600"
			}, timeout, interval).Should(BeTrue())
		})
	})

	Describe("Specific Workload Targeting", func() {
		It("should apply policy to specifically targeted workloads", func() {
			// 1. 여러 워크로드 생성
			deployments := []*appsv1.Deployment{
				createTestDeployment("target-deployment", namespace, map[string]string{"app": "target"}),
				createTestDeployment("other-deployment", namespace, map[string]string{"app": "other"}),
			}

			for _, deployment := range deployments {
				Expect(k8sClient.Create(ctx, deployment)).Should(Succeed())
			}

			// 2. 특정 워크로드만 타겟팅하는 정책 생성
			policy := &opensdiv1alpha1.MALEPolicy{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "specific-target-policy",
					Namespace: namespace,
				},
				Spec: opensdiv1alpha1.MALEPolicySpec{
					Accuracy: 900,
					Latency:  100,
					Energy:   500,
					TargetWorkloads: []opensdiv1alpha1.WorkloadTarget{
						{
							Name:      "target-deployment",
							Namespace: namespace,
							Kind:      "Deployment",
						},
					},
					Description: "Policy for specific workload",
				},
			}
			Expect(k8sClient.Create(ctx, policy)).Should(Succeed())

			// 3. 타겟 워크로드에만 적용되었는지 확인
			Eventually(func() bool {
				var targetDeployment appsv1.Deployment
				err := k8sClient.Get(ctx, types.NamespacedName{
					Name:      "target-deployment",
					Namespace: namespace,
				}, &targetDeployment)
				if err != nil {
					return false
				}

				annotations := targetDeployment.Annotations
				return annotations != nil && annotations["male-policy.opensdi.io/accuracy"] == "900"
			}, timeout, interval).Should(BeTrue())

			// 4. 다른 워크로드에는 적용되지 않았는지 확인
			Consistently(func() bool {
				var otherDeployment appsv1.Deployment
				err := k8sClient.Get(ctx, types.NamespacedName{
					Name:      "other-deployment",
					Namespace: namespace,
				}, &otherDeployment)
				if err != nil {
					return false
				}

				annotations := otherDeployment.Annotations
				return annotations == nil || annotations["male-policy.opensdi.io/accuracy"] == ""
			}, time.Second*10, interval).Should(BeTrue())
		})
	})

	Describe("Policy Priority and Conflicts", func() {
		It("should handle multiple policies with proper priority", func() {
			// 1. 테스트 워크로드 생성
			deployment := createTestDeployment("priority-test", namespace, map[string]string{
				"app":  "priority-test",
				"type": "ml",
			})
			Expect(k8sClient.Create(ctx, deployment)).Should(Succeed())

			// 2. 글로벌 기본 정책 생성
			globalPolicy := &opensdiv1alpha1.MALEPolicy{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "global-policy",
					Namespace: namespace,
				},
				Spec: opensdiv1alpha1.MALEPolicySpec{
					Accuracy:      500,
					Latency:       500,
					Energy:        500,
					GlobalDefault: true,
					Description:   "Global default policy",
				},
			}
			Expect(k8sClient.Create(ctx, globalPolicy)).Should(Succeed())

			// 3. 셀렉터 기반 정책 생성
			selectorPolicy := &opensdiv1alpha1.MALEPolicy{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "selector-policy",
					Namespace: namespace,
				},
				Spec: opensdiv1alpha1.MALEPolicySpec{
					Accuracy: 700,
					Latency:  300,
					Energy:   600,
					Selector: map[string]string{
						"type": "ml",
					},
					Description: "Selector-based policy",
				},
			}
			Expect(k8sClient.Create(ctx, selectorPolicy)).Should(Succeed())

			// 4. 특정 워크로드 정책 생성 (최고 우선순위)
			specificPolicy := &opensdiv1alpha1.MALEPolicy{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "specific-policy",
					Namespace: namespace,
				},
				Spec: opensdiv1alpha1.MALEPolicySpec{
					Accuracy: 950,
					Latency:  50,
					Energy:   400,
					TargetWorkloads: []opensdiv1alpha1.WorkloadTarget{
						{
							Name:      "priority-test",
							Namespace: namespace,
							Kind:      "Deployment",
						},
					},
					Description: "Specific workload policy (highest priority)",
				},
			}
			Expect(k8sClient.Create(ctx, specificPolicy)).Should(Succeed())

			// 5. 특정 워크로드 정책이 적용되었는지 확인 (최고 우선순위)
			Eventually(func() bool {
				var updatedDeployment appsv1.Deployment
				err := k8sClient.Get(ctx, types.NamespacedName{
					Name:      "priority-test",
					Namespace: namespace,
				}, &updatedDeployment)
				if err != nil {
					return false
				}

				annotations := updatedDeployment.Annotations
				return annotations != nil &&
					annotations["male-policy.opensdi.io/accuracy"] == "950" &&
					annotations["male-policy.opensdi.io/policy-name"] == "specific-policy"
			}, timeout, interval).Should(BeTrue())
		})
	})

	Describe("Policy Validation", func() {
		It("should reject invalid policy configurations", func() {
			// 1. 잘못된 MALE 값 조합 테스트
			invalidPolicy := &opensdiv1alpha1.MALEPolicy{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "invalid-policy",
					Namespace: namespace,
				},
				Spec: opensdiv1alpha1.MALEPolicySpec{
					Accuracy:    1500, // 유효 범위 초과
					Latency:     -100, // 음수
					Energy:      2000, // 유효 범위 초과
					Description: "Invalid policy for testing",
				},
			}

			// 2. 정책 생성이 실패해야 함
			err := k8sClient.Create(ctx, invalidPolicy)
			Expect(err).Should(HaveOccurred())
		})

		It("should warn about unrealistic MALE combinations", func() {
			// 이 테스트는 실제로는 admission webhook나 validation logic에서 처리됨
			// 현재는 기본 kubebuilder validation만 있음
			Skip("Validation webhook not implemented yet")
		})
	})

	Describe("Dynamic Policy Updates", func() {
		It("should update workloads when policy changes", func() {
			// 1. 워크로드와 초기 정책 생성
			deployment := createTestDeployment("update-test", namespace, map[string]string{
				"app": "update-test",
			})
			Expect(k8sClient.Create(ctx, deployment)).Should(Succeed())

			policy := &opensdiv1alpha1.MALEPolicy{
				ObjectMeta: metav1.ObjectMeta{
					Name:      "update-policy",
					Namespace: namespace,
				},
				Spec: opensdiv1alpha1.MALEPolicySpec{
					Accuracy: 600,
					Latency:  400,
					Energy:   700,
					TargetWorkloads: []opensdiv1alpha1.WorkloadTarget{
						{
							Name:      "update-test",
							Namespace: namespace,
							Kind:      "Deployment",
						},
					},
					Description: "Policy for update testing",
				},
			}
			Expect(k8sClient.Create(ctx, policy)).Should(Succeed())

			// 2. 초기 정책 적용 확인
			Eventually(func() bool {
				var updatedDeployment appsv1.Deployment
				err := k8sClient.Get(ctx, types.NamespacedName{
					Name:      "update-test",
					Namespace: namespace,
				}, &updatedDeployment)
				if err != nil {
					return false
				}

				annotations := updatedDeployment.Annotations
				return annotations != nil && annotations["male-policy.opensdi.io/accuracy"] == "600"
			}, timeout, interval).Should(BeTrue())

			// 3. 정책 업데이트
			var updatedPolicy opensdiv1alpha1.MALEPolicy
			Expect(k8sClient.Get(ctx, types.NamespacedName{
				Name:      policy.Name,
				Namespace: namespace,
			}, &updatedPolicy)).Should(Succeed())

			updatedPolicy.Spec.Accuracy = 850
			updatedPolicy.Spec.Latency = 150
			updatedPolicy.Spec.Energy = 550

			Expect(k8sClient.Update(ctx, &updatedPolicy)).Should(Succeed())

			// 4. 업데이트된 정책이 적용되었는지 확인
			Eventually(func() bool {
				var deployment appsv1.Deployment
				err := k8sClient.Get(ctx, types.NamespacedName{
					Name:      "update-test",
					Namespace: namespace,
				}, &deployment)
				if err != nil {
					return false
				}

				annotations := deployment.Annotations
				return annotations != nil &&
					annotations["male-policy.opensdi.io/accuracy"] == "850" &&
					annotations["male-policy.opensdi.io/latency"] == "150" &&
					annotations["male-policy.opensdi.io/energy"] == "550"
			}, timeout, interval).Should(BeTrue())
		})
	})

	Describe("Health and Monitoring", func() {
		It("should expose health endpoints", func() {
			// 이 테스트는 실제 HTTP 요청을 통해 확인해야 함
			// 통합 테스트 환경에서는 포트 포워딩이나 서비스 접근을 통해 테스트
			Skip("Health endpoint testing requires HTTP client setup")
		})

		It("should emit metrics for policy applications", func() {
			// 메트릭 테스트는 Prometheus 클라이언트나 메트릭 레지스트리 접근이 필요
			Skip("Metrics testing requires Prometheus client setup")
		})
	})
})

// 헬퍼 함수들
func createTestDeployment(name, namespace string, labels map[string]string) *appsv1.Deployment {
	return &appsv1.Deployment{
		ObjectMeta: metav1.ObjectMeta{
			Name:      name,
			Namespace: namespace,
			Labels:    labels,
		},
		Spec: appsv1.DeploymentSpec{
			Replicas: int32Ptr(1),
			Selector: &metav1.LabelSelector{
				MatchLabels: map[string]string{
					"app": name,
				},
			},
			Template: corev1.PodTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{
					Labels: labels,
				},
				Spec: corev1.PodSpec{
					Containers: []corev1.Container{
						{
							Name:  "test-container",
							Image: "nginx:latest",
							Ports: []corev1.ContainerPort{
								{
									ContainerPort: 80,
								},
							},
						},
					},
				},
			},
		},
	}
}

func int32Ptr(i int32) *int32 {
	return &i
}
