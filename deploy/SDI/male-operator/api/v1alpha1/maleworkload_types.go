/*
Copyright 2024 KETI.

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

// MaleWorkloadSpec defines the desired state of MaleWorkload
type MaleWorkloadSpec struct {
	// TargetRef specifies the target workload resource
	// +kubebuilder:validation:Required
	TargetRef TargetReference `json:"targetRef"`

	// Mission is a descriptive name for the workload mission
	// +kubebuilder:validation:Optional
	Mission string `json:"mission,omitempty"`

	// Importance defines the user-specified A,L,E values (0~1 float)
	// +kubebuilder:validation:Required
	Importance ImportanceValues `json:"importance"`

	// AllowPolicyOverride allows policy engine to override importance values
	// +kubebuilder:default=true
	AllowPolicyOverride bool `json:"allowPolicyOverride,omitempty"`

	// SchedulingHints provides additional hints for scheduling
	// +kubebuilder:validation:Optional
	SchedulingHints SchedulingHints `json:"schedulingHints,omitempty"`
}

// TargetReference specifies the target workload
type TargetReference struct {
	// APIVersion of the target resource
	// +kubebuilder:validation:Required
	APIVersion string `json:"apiVersion"`

	// Kind of the target resource (Deployment, StatefulSet, Job, Pod, etc.)
	// +kubebuilder:validation:Required
	Kind string `json:"kind"`

	// Name of the target resource
	// +kubebuilder:validation:Required
	Name string `json:"name"`
}

// ImportanceValues defines the A,L,E importance values
type ImportanceValues struct {
	// Accuracy importance value in range [0,1]
	// +kubebuilder:validation:Minimum=0
	// +kubebuilder:validation:Maximum=1
	Accuracy float64 `json:"accuracy"`

	// Latency importance value in range [0,1]
	// +kubebuilder:validation:Minimum=0
	// +kubebuilder:validation:Maximum=1
	Latency float64 `json:"latency"`

	// Energy importance value in range [0,1]
	// +kubebuilder:validation:Minimum=0
	// +kubebuilder:validation:Maximum=1
	Energy float64 `json:"energy"`
}

// SchedulingHints provides hints for scheduling
type SchedulingHints struct {
	// AddLabels are labels to add to the Pod template
	// +kubebuilder:validation:Optional
	AddLabels map[string]string `json:"addLabels,omitempty"`

	// AddAnnotations are annotations to add to the Pod template
	// +kubebuilder:validation:Optional
	AddAnnotations map[string]string `json:"addAnnotations,omitempty"`
}

// MaleWorkloadStatus defines the observed state of MaleWorkload
type MaleWorkloadStatus struct {
	// EffectiveImportance shows the importance values after override application
	// +kubebuilder:validation:Optional
	EffectiveImportance *ImportanceValues `json:"effectiveImportance,omitempty"`

	// MixedScore is the calculated mixed importance score (0~1)
	// +kubebuilder:validation:Optional
	MixedScore *float64 `json:"mixedScore,omitempty"`

	// PriorityClassName is the PriorityClass name assigned to this workload
	// +kubebuilder:validation:Optional
	PriorityClassName string `json:"priorityClassName,omitempty"`

	// LastEvaluationTime is the timestamp of the last evaluation
	// +kubebuilder:validation:Optional
	LastEvaluationTime *metav1.Time `json:"lastEvaluationTime,omitempty"`

	// Conditions represent the latest available observations of the workload's state
	// +kubebuilder:validation:Optional
	Conditions []metav1.Condition `json:"conditions,omitempty"`
}

//+kubebuilder:object:root=true
//+kubebuilder:subresource:status
//+kubebuilder:resource:scope=Namespaced

// MaleWorkload is the Schema for the maleworkloads API
type MaleWorkload struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   MaleWorkloadSpec   `json:"spec,omitempty"`
	Status MaleWorkloadStatus `json:"status,omitempty"`
}

//+kubebuilder:object:root=true

// MaleWorkloadList contains a list of MaleWorkload
type MaleWorkloadList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []MaleWorkload `json:"items"`
}

func init() {
	SchemeBuilder.Register(&MaleWorkload{}, &MaleWorkloadList{})
}

