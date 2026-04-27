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

package webhook

import (
	"context"

	"sigs.k8s.io/controller-runtime/pkg/webhook/admission"

	malev1alpha1 "github.com/keti-lab/male-operator/api/v1alpha1"
)

// MalePolicyValidator validates MalePolicy resources
type MalePolicyValidator struct {
	decoder admission.Decoder
}

// NewMalePolicyValidator creates a new MalePolicyValidator
func NewMalePolicyValidator() *MalePolicyValidator {
	return &MalePolicyValidator{}
}

// InjectDecoder injects the decoder
func (v *MalePolicyValidator) InjectDecoder(d admission.Decoder) error {
	v.decoder = d
	return nil
}

// Handle handles MalePolicy validation requests
func (v *MalePolicyValidator) Handle(ctx context.Context, req admission.Request) admission.Response {
	policy := &malev1alpha1.MalePolicy{}
	if err := v.decoder.Decode(req, policy); err != nil {
		return admission.Errored(400, err)
	}

	// Validate weights
	if err := policy.ValidateWeights(); err != nil {
		return admission.Denied(err.Error())
	}

	// Validate priority buckets
	if err := policy.ValidatePriorityBuckets(); err != nil {
		return admission.Denied(err.Error())
	}

	return admission.Allowed("")
}

// MaleWorkloadValidator validates MaleWorkload resources
type MaleWorkloadValidator struct {
	decoder admission.Decoder
}

// NewMaleWorkloadValidator creates a new MaleWorkloadValidator
func NewMaleWorkloadValidator() *MaleWorkloadValidator {
	return &MaleWorkloadValidator{}
}

// InjectDecoder injects the decoder
func (v *MaleWorkloadValidator) InjectDecoder(d admission.Decoder) error {
	v.decoder = d
	return nil
}

// Handle handles MaleWorkload validation requests
func (v *MaleWorkloadValidator) Handle(ctx context.Context, req admission.Request) admission.Response {
	workload := &malev1alpha1.MaleWorkload{}
	if err := v.decoder.Decode(req, workload); err != nil {
		return admission.Errored(400, err)
	}

	// Validate importance values are in [0,1]
	imp := workload.Spec.Importance
	if imp.Accuracy < 0 || imp.Accuracy > 1 {
		return admission.Denied("importance.accuracy must be in [0,1]")
	}
	if imp.Latency < 0 || imp.Latency > 1 {
		return admission.Denied("importance.latency must be in [0,1]")
	}
	if imp.Energy < 0 || imp.Energy > 1 {
		return admission.Denied("importance.energy must be in [0,1]")
	}

	return admission.Allowed("")
}
