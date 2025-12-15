package validation

import (
	"fmt"
	"strings"

	"k8s.io/apimachinery/pkg/util/validation/field"
	opensdiv1alpha1 "male-policy-controller/api/v1alpha1"
)

// PolicyValidator validates MALE policies
type PolicyValidator struct{}

// ValidatePolicy performs comprehensive validation of a MALE policy
func (v *PolicyValidator) ValidatePolicy(policy *opensdiv1alpha1.MALEPolicy) error {
	var allErrs field.ErrorList

	// 기본 MALE 값 범위 검증
	if err := v.validateMALEValues(policy); err != nil {
		allErrs = append(allErrs, err...)
	}

	// MALE 값 조합 유효성 검증
	if err := v.validateMALECombination(policy); err != nil {
		allErrs = append(allErrs, err...)
	}

	// 타겟 워크로드 검증
	if err := v.validateTargetWorkloads(policy); err != nil {
		allErrs = append(allErrs, err...)
	}

	// 셀렉터 검증
	if err := v.validateSelector(policy); err != nil {
		allErrs = append(allErrs, err...)
	}

	// 정책 충돌 검증
	if err := v.validatePolicyConflicts(policy); err != nil {
		allErrs = append(allErrs, err...)
	}

	if len(allErrs) > 0 {
		return allErrs.ToAggregate()
	}

	return nil
}

// validateMALEValues validates individual MALE values
func (v *PolicyValidator) validateMALEValues(policy *opensdiv1alpha1.MALEPolicy) field.ErrorList {
	var allErrs field.ErrorList
	specPath := field.NewPath("spec")

	// 범위 검증은 이미 kubebuilder에서 처리되지만 추가 검증
	if policy.Spec.Accuracy < 0 || policy.Spec.Accuracy > 1000 {
		allErrs = append(allErrs, field.Invalid(specPath.Child("accuracy"), policy.Spec.Accuracy, "must be between 0 and 1000"))
	}

	if policy.Spec.Latency < 0 || policy.Spec.Latency > 1000 {
		allErrs = append(allErrs, field.Invalid(specPath.Child("latency"), policy.Spec.Latency, "must be between 0 and 1000"))
	}

	if policy.Spec.Energy < 0 || policy.Spec.Energy > 1000 {
		allErrs = append(allErrs, field.Invalid(specPath.Child("energy"), policy.Spec.Energy, "must be between 0 and 1000"))
	}

	return allErrs
}

// validateMALECombination validates if MALE value combinations make sense
func (v *PolicyValidator) validateMALECombination(policy *opensdiv1alpha1.MALEPolicy) field.ErrorList {
	var allErrs field.ErrorList
	specPath := field.NewPath("spec")

	accuracy := policy.Spec.Accuracy
	latency := policy.Spec.Latency
	energy := policy.Spec.Energy

	// 논리적으로 모순되는 조합 검증

	// 매우 높은 정확도 + 매우 낮은 지연시간 + 매우 높은 에너지 효율 = 현실적으로 불가능
	if accuracy > 900 && latency < 100 && energy > 900 {
		allErrs = append(allErrs, field.Invalid(
			specPath,
			fmt.Sprintf("accuracy=%d, latency=%d, energy=%d", accuracy, latency, energy),
			"combination of very high accuracy, very low latency, and very high energy efficiency is unrealistic",
		))
	}

	// 매우 낮은 정확도 + 매우 높은 지연시간 허용 = 의미없는 조합
	if accuracy < 100 && latency > 900 {
		allErrs = append(allErrs, field.Invalid(
			specPath,
			fmt.Sprintf("accuracy=%d, latency=%d", accuracy, latency),
			"very low accuracy with very high latency tolerance may indicate misconfiguration",
		))
	}

	// 모든 값이 극단적으로 낮음 = 워크로드가 제대로 동작하지 않을 가능성
	if accuracy < 100 && latency < 100 && energy < 100 {
		allErrs = append(allErrs, field.Invalid(
			specPath,
			"all MALE values are extremely low",
			"this configuration may result in poor workload performance",
		))
	}

	return allErrs
}

// validateTargetWorkloads validates target workload specifications
func (v *PolicyValidator) validateTargetWorkloads(policy *opensdiv1alpha1.MALEPolicy) field.ErrorList {
	var allErrs field.ErrorList
	specPath := field.NewPath("spec").Child("targetWorkloads")

	for i, target := range policy.Spec.TargetWorkloads {
		targetPath := specPath.Index(i)

		// 이름 검증
		if target.Name == "" {
			allErrs = append(allErrs, field.Required(targetPath.Child("name"), "workload name is required"))
		}

		// 네임스페이스 검증
		if target.Namespace == "" {
			allErrs = append(allErrs, field.Required(targetPath.Child("namespace"), "workload namespace is required"))
		}

		// Kind 검증
		validKinds := []string{"Deployment", "StatefulSet", "DaemonSet"}
		if !contains(validKinds, target.Kind) {
			allErrs = append(allErrs, field.NotSupported(
				targetPath.Child("kind"),
				target.Kind,
				validKinds,
			))
		}

		// 중복 타겟 검증
		for j, other := range policy.Spec.TargetWorkloads[i+1:] {
			if target.Name == other.Name && target.Namespace == other.Namespace && target.Kind == other.Kind {
				allErrs = append(allErrs, field.Duplicate(
					targetPath,
					fmt.Sprintf("duplicate target workload at index %d", i+j+1),
				))
			}
		}
	}

	return allErrs
}

// validateSelector validates label selector
func (v *PolicyValidator) validateSelector(policy *opensdiv1alpha1.MALEPolicy) field.ErrorList {
	var allErrs field.ErrorList
	specPath := field.NewPath("spec").Child("selector")

	for key, value := range policy.Spec.Selector {
		// 키 검증
		if strings.TrimSpace(key) == "" {
			allErrs = append(allErrs, field.Invalid(specPath.Key(key), key, "selector key cannot be empty"))
		}

		// 값 검증
		if strings.TrimSpace(value) == "" {
			allErrs = append(allErrs, field.Invalid(specPath.Key(key), value, "selector value cannot be empty"))
		}

		// Kubernetes 라벨 규칙 준수 확인 (간단한 버전)
		if len(key) > 63 {
			allErrs = append(allErrs, field.TooLong(specPath.Key(key), key, 63))
		}

		if len(value) > 63 {
			allErrs = append(allErrs, field.TooLong(specPath.Key(key), value, 63))
		}
	}

	return allErrs
}

// validatePolicyConflicts validates potential conflicts between policies
func (v *PolicyValidator) validatePolicyConflicts(policy *opensdiv1alpha1.MALEPolicy) field.ErrorList {
	var allErrs field.ErrorList

	// GlobalDefault 정책이 여러 개인지 확인 (실제로는 다른 정책들과 비교해야 함)
	if policy.Spec.GlobalDefault {
		// 여기서는 경고만 생성
		// 실제 구현에서는 클러스터의 다른 GlobalDefault 정책과 비교해야 함
	}

	// TargetWorkloads와 Selector가 모두 비어있고 GlobalDefault도 false인 경우
	if len(policy.Spec.TargetWorkloads) == 0 && len(policy.Spec.Selector) == 0 && !policy.Spec.GlobalDefault {
		allErrs = append(allErrs, field.Invalid(
			field.NewPath("spec"),
			"no targeting configuration",
			"policy must specify either targetWorkloads, selector, or set globalDefault to true",
		))
	}

	return allErrs
}

// contains checks if a slice contains a string
func contains(slice []string, item string) bool {
	for _, s := range slice {
		if s == item {
			return true
		}
	}
	return false
}

// ValidateUpdate validates policy updates
func (v *PolicyValidator) ValidateUpdate(oldPolicy, newPolicy *opensdiv1alpha1.MALEPolicy) error {
	var allErrs field.ErrorList

	// 기본 검증
	if err := v.ValidatePolicy(newPolicy); err != nil {
		return err
	}

	// 업데이트 특화 검증

	// MALE 값 급격한 변화 감지
	if v.hasSignificantChange(oldPolicy, newPolicy) {
		allErrs = append(allErrs, field.Invalid(
			field.NewPath("spec"),
			"significant MALE value change detected",
			"consider gradual changes to avoid workload disruption",
		))
	}

	// GlobalDefault 변경 제한
	if oldPolicy.Spec.GlobalDefault != newPolicy.Spec.GlobalDefault {
		allErrs = append(allErrs, field.Forbidden(
			field.NewPath("spec").Child("globalDefault"),
			"changing globalDefault flag is not allowed, create a new policy instead",
		))
	}

	if len(allErrs) > 0 {
		return allErrs.ToAggregate()
	}

	return nil
}

// hasSignificantChange checks if MALE values changed significantly
func (v *PolicyValidator) hasSignificantChange(oldPolicy, newPolicy *opensdiv1alpha1.MALEPolicy) bool {
	threshold := int32(200) // 20% 변화 임계값

	accuracyChange := abs(newPolicy.Spec.Accuracy - oldPolicy.Spec.Accuracy)
	latencyChange := abs(newPolicy.Spec.Latency - oldPolicy.Spec.Latency)
	energyChange := abs(newPolicy.Spec.Energy - oldPolicy.Spec.Energy)

	return accuracyChange > threshold || latencyChange > threshold || energyChange > threshold
}

// abs returns absolute value of int32
func abs(x int32) int32 {
	if x < 0 {
		return -x
	}
	return x
}
