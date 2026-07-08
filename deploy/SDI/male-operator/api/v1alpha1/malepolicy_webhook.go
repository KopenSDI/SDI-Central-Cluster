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
	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/webhook"
	"sigs.k8s.io/controller-runtime/pkg/webhook/admission"
)

//+kubebuilder:webhook:path=/validate-male-keti-dev-v1alpha1-malepolicy,mutating=false,failurePolicy=fail,sideEffects=None,groups=male.keti.dev,resources=malepolicies,verbs=create;update,versions=v1alpha1,name=vmalepolicy.kb.io,admissionReviewVersions=v1

var _ webhook.Validator = &MalePolicy{}

// ValidateCreate implements webhook.Validator so a webhook will be registered for the type
func (r *MalePolicy) ValidateCreate() (admission.Warnings, error) {
	if err := r.ValidateWeights(); err != nil {
		return nil, err
	}
	if err := r.ValidatePriorityBuckets(); err != nil {
		return nil, err
	}
	return nil, nil
}

// ValidateUpdate implements webhook.Validator so a webhook will be registered for the type
func (r *MalePolicy) ValidateUpdate(old runtime.Object) (admission.Warnings, error) {
	return r.ValidateCreate()
}

// ValidateDelete implements webhook.Validator so a webhook will be registered for the type
func (r *MalePolicy) ValidateDelete() (admission.Warnings, error) {
	return nil, nil
}

// SetupWebhookWithManager sets up the webhook with the manager
func (r *MalePolicy) SetupWebhookWithManager(mgr ctrl.Manager) error {
	return ctrl.NewWebhookManagedBy(mgr).
		For(r).
		Complete()
}
