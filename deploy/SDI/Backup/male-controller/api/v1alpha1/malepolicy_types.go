/*
Copyright 2025.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// EDIT THIS FILE!  THIS IS SCAFFOLDING FOR YOU TO OWN!
// NOTE: json tags are required.  Any new fields you add must have json tags for the fields to be serialized.

// MALEPolicySpec defines the desired state of MALEPolicy
type MALEPolicySpec struct {
	// 정확도 요구 수준 (0–1000)
	// +kubebuilder:validation:Minimum=0
	// +kubebuilder:validation:Maximum=1000
	Accuracy int32 `json:"accuracy"`

	// 지연 민감도 (0–1000)
	// +kubebuilder:validation:Minimum=0
	// +kubebuilder:validation:Maximum=1000
	Latency int32 `json:"latency"`

	// 전력 효율 (0–1000)
	// +kubebuilder:validation:Minimum=0
	// +kubebuilder:validation:Maximum=1000
	Energy int32 `json:"energy"`

	// 워크로드 선택을 위한 라벨 셀렉터
	// +optional
	Selector map[string]string `json:"selector,omitempty"`

	// 특정 워크로드 이름으로 직접 지정
	// +optional
	TargetWorkloads []WorkloadTarget `json:"targetWorkloads,omitempty"`

	// 네임스페이스 선택 (빈 값이면 모든 네임스페이스)
	// +optional
	TargetNamespaces []string `json:"targetNamespaces,omitempty"`

	Description      string `json:"description,omitempty"`
	GlobalDefault    bool   `json:"globalDefault,omitempty"`
	PreemptionPolicy string `json:"preemptionPolicy,omitempty"`
}

// MALEPolicyStatus defines the observed state of MALEPolicy.
type MALEPolicyStatus struct {
	// 적용된 워크로드 개수
	AppliedWorkloads int32 `json:"appliedWorkloads,omitempty"`

	// 적용된 워크로드 목록
	WorkloadStatus []WorkloadStatus `json:"workloadStatus,omitempty"`

	// 마지막 업데이트 시간
	LastUpdated string `json:"lastUpdated,omitempty"`
}

// WorkloadTarget represents a specific workload to target
type WorkloadTarget struct {
	Name      string `json:"name"`
	Namespace string `json:"namespace"`
	Kind      string `json:"kind"` // Deployment, StatefulSet, DaemonSet
}

// WorkloadStatus represents the status of a workload affected by this policy
type WorkloadStatus struct {
	Name      string `json:"name"`
	Namespace string `json:"namespace"`
	Kind      string `json:"kind"`
	Status    string `json:"status"` // Applied, Failed, Pending
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status

// MALEPolicy is the Schema for the malepolicies API
type MALEPolicy struct {
	metav1.TypeMeta `json:",inline"`

	// metadata is a standard object metadata
	// +optional
	metav1.ObjectMeta `json:"metadata,omitempty,omitzero"`

	// spec defines the desired state of MALEPolicy
	// +required
	Spec MALEPolicySpec `json:"spec"`

	// status defines the observed state of MALEPolicy
	// +optional
	Status MALEPolicyStatus `json:"status,omitempty,omitzero"`
}

// +kubebuilder:object:root=true

// MALEPolicyList contains a list of MALEPolicy
type MALEPolicyList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []MALEPolicy `json:"items"`
}

func init() {
	SchemeBuilder.Register(&MALEPolicy{}, &MALEPolicyList{})
}
