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

// MalePolicySpec defines the desired state of MalePolicy
type MalePolicySpec struct {
	// Weights defines the weight for each dimension (accuracy, latency, energy)
	// The sum of all weights must equal 1.0
	// +kubebuilder:validation:Required
	Weights Weights `json:"weights"`

	// Bounds defines the min/max bounds for each dimension
	// Values will be clamped to these bounds after override
	// +kubebuilder:validation:Required
	Bounds Bounds `json:"bounds"`

	// Override configuration for policy engine overrides
	// +kubebuilder:validation:Optional
	Override OverrideConfig `json:"override,omitempty"`

	// PriorityBuckets maps score ranges to PriorityClass values
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinItems=1
	PriorityBuckets []PriorityBucket `json:"priorityBuckets"`
}

// Weights defines the weight for each dimension
type Weights struct {
	// Accuracy weight (wA) in range [0,1]
	// +kubebuilder:validation:Minimum=0
	// +kubebuilder:validation:Maximum=1
	// +kubebuilder:default=0.5
	Accuracy float64 `json:"accuracy"`

	// Latency weight (wL) in range [0,1]
	// +kubebuilder:validation:Minimum=0
	// +kubebuilder:validation:Maximum=1
	// +kubebuilder:default=0.3
	Latency float64 `json:"latency"`

	// Energy weight (wE) in range [0,1]
	// +kubebuilder:validation:Minimum=0
	// +kubebuilder:validation:Maximum=1
	// +kubebuilder:default=0.2
	Energy float64 `json:"energy"`
}

// Bounds defines min/max bounds for each dimension
type Bounds struct {
	// Accuracy bounds
	// +kubebuilder:validation:Required
	Accuracy MinMax `json:"accuracy"`

	// Latency bounds
	// +kubebuilder:validation:Required
	Latency MinMax `json:"latency"`

	// Energy bounds
	// +kubebuilder:validation:Required
	Energy MinMax `json:"energy"`
}

// MinMax defines a range
type MinMax struct {
	// Minimum value (inclusive)
	// +kubebuilder:validation:Minimum=0
	// +kubebuilder:validation:Maximum=1
	Min float64 `json:"min"`

	// Maximum value (inclusive)
	// +kubebuilder:validation:Minimum=0
	// +kubebuilder:validation:Maximum=1
	Max float64 `json:"max"`
}

// OverrideConfig defines override source configuration
type OverrideConfig struct {
	// Enabled enables override functionality
	// +kubebuilder:default=true
	Enabled bool `json:"enabled,omitempty"`

	// Source defines where to read override values from
	// +kubebuilder:validation:Optional
	Source OverrideSource `json:"source,omitempty"`

	// WebhookReceiver configuration for HTTP endpoint receiver
	// +kubebuilder:validation:Optional
	WebhookReceiver WebhookReceiverConfig `json:"webhookReceiver,omitempty"`
}

// OverrideSource defines the source for override values
type OverrideSource struct {
	// Type of source: ConfigMap or Webhook
	// +kubebuilder:validation:Enum=ConfigMap;Webhook
	// +kubebuilder:default=ConfigMap
	Type string `json:"type"`

	// Name of the ConfigMap (if type is ConfigMap)
	// +kubebuilder:validation:Optional
	Name string `json:"name,omitempty"`

	// Namespace of the ConfigMap (if type is ConfigMap)
	// +kubebuilder:validation:Optional
	Namespace string `json:"namespace,omitempty"`
}

// WebhookReceiverConfig defines webhook receiver configuration
type WebhookReceiverConfig struct {
	// Enabled enables webhook receiver
	// +kubebuilder:default=false
	Enabled bool `json:"enabled,omitempty"`

	// ServiceName is the name of the service exposing the webhook
	// +kubebuilder:validation:Optional
	ServiceName string `json:"serviceName,omitempty"`

	// Port is the port number for the webhook service
	// +kubebuilder:validation:Minimum=1
	// +kubebuilder:validation:Maximum=65535
	// +kubebuilder:default=9443
	Port int32 `json:"port,omitempty"`

	// Path is the HTTP path for override endpoint
	// +kubebuilder:default="/override"
	Path string `json:"path,omitempty"`
}

// PriorityBucket maps a score range to a PriorityClass
type PriorityBucket struct {
	// Name of the PriorityClass to create/update
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	Name string `json:"name"`

	// Min score (inclusive) in range [0,1]
	// +kubebuilder:validation:Minimum=0
	// +kubebuilder:validation:Maximum=1
	Min float64 `json:"min"`

	// Max score (inclusive) in range [0,1]
	// +kubebuilder:validation:Minimum=0
	// +kubebuilder:validation:Maximum=1
	Max float64 `json:"max"`

	// PriorityValue is the priority value for the PriorityClass
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Minimum=0
	PriorityValue int32 `json:"priorityValue"`
}

// MalePolicyStatus defines the observed state of MalePolicy
type MalePolicyStatus struct {
	// EffectiveWeights shows the weights after override application
	// +kubebuilder:validation:Optional
	EffectiveWeights *Weights `json:"effectiveWeights,omitempty"`

	// LastOverrideSource indicates the last source used for override
	// +kubebuilder:validation:Optional
	LastOverrideSource string `json:"lastOverrideSource,omitempty"`

	// Conditions represent the latest available observations of the policy's state
	// +kubebuilder:validation:Optional
	Conditions []metav1.Condition `json:"conditions,omitempty"`
}

//+kubebuilder:object:root=true
//+kubebuilder:subresource:status
//+kubebuilder:resource:scope=Cluster

// MalePolicy is the Schema for the malepolicies API
type MalePolicy struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   MalePolicySpec   `json:"spec,omitempty"`
	Status MalePolicyStatus `json:"status,omitempty"`
}

//+kubebuilder:object:root=true

// MalePolicyList contains a list of MalePolicy
type MalePolicyList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []MalePolicy `json:"items"`
}

func init() {
	SchemeBuilder.Register(&MalePolicy{}, &MalePolicyList{})
}
