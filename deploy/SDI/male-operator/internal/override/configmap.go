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

package override

import (
	"context"
	"encoding/json"
	"fmt"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"

	malev1alpha1 "github.com/keti-lab/male-operator/api/v1alpha1"
)

// OverrideValue represents an override value from ConfigMap
type OverrideValue struct {
	Accuracy *float64 `json:"accuracy,omitempty"`
	Latency  *float64 `json:"latency,omitempty"`
	Energy   *float64 `json:"energy,omitempty"`
	Reason   string   `json:"reason,omitempty"`
}

// ConfigMapReader reads override values from ConfigMap
type ConfigMapReader struct {
	client client.Client
}

// NewConfigMapReader creates a new ConfigMapReader
func NewConfigMapReader(client client.Client) *ConfigMapReader {
	return &ConfigMapReader{client: client}
}

// GetOverride reads override values from ConfigMap for a specific workload
// Key format: <namespace>.<maleworkload-name>.json
func (r *ConfigMapReader) GetOverride(ctx context.Context, source malev1alpha1.OverrideSource, namespace, workloadName string) (*OverrideValue, error) {
	if source.Type != "ConfigMap" {
		return nil, fmt.Errorf("source type is not ConfigMap: %s", source.Type)
	}

	if source.Name == "" || source.Namespace == "" {
		return nil, fmt.Errorf("ConfigMap name and namespace must be specified")
	}

	configMap := &corev1.ConfigMap{}
	key := types.NamespacedName{
		Namespace: source.Namespace,
		Name:      source.Name,
	}

	if err := r.client.Get(ctx, key, configMap); err != nil {
		return nil, fmt.Errorf("failed to get ConfigMap %s/%s: %w", source.Namespace, source.Name, err)
	}

	// Try specific key first: <namespace>.<maleworkload-name>.json
	specificKey := fmt.Sprintf("%s.%s.json", namespace, workloadName)
	if data, ok := configMap.Data[specificKey]; ok {
		return parseOverrideJSON(data)
	}

	// Try generic key: <maleworkload-name>.json
	genericKey := fmt.Sprintf("%s.json", workloadName)
	if data, ok := configMap.Data[genericKey]; ok {
		return parseOverrideJSON(data)
	}

	// No override found
	return nil, nil
}

func parseOverrideJSON(data string) (*OverrideValue, error) {
	var override OverrideValue
	if err := json.Unmarshal([]byte(data), &override); err != nil {
		return nil, fmt.Errorf("failed to parse override JSON: %w", err)
	}
	return &override, nil
}

// ApplyOverride applies override values to importance values
func ApplyOverride(importance malev1alpha1.ImportanceValues, override *OverrideValue) malev1alpha1.ImportanceValues {
	result := importance

	if override.Accuracy != nil {
		result.Accuracy = *override.Accuracy
	}
	if override.Latency != nil {
		result.Latency = *override.Latency
	}
	if override.Energy != nil {
		result.Energy = *override.Energy
	}

	return result
}
