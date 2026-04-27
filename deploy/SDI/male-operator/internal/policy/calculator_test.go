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

package policy

import (
	"testing"

	malev1alpha1 "github.com/keti-lab/male-operator/api/v1alpha1"
)

func TestCalculateMixedScore(t *testing.T) {
	tests := []struct {
		name       string
		weights    malev1alpha1.Weights
		importance malev1alpha1.ImportanceValues
		wantScore  float64
		wantErr    bool
	}{
		{
			name: "valid calculation",
			weights: malev1alpha1.Weights{
				Accuracy: 0.5,
				Latency:  0.3,
				Energy:   0.2,
			},
			importance: malev1alpha1.ImportanceValues{
				Accuracy: 0.7,
				Latency:  0.8,
				Energy:   0.2,
			},
			wantScore: 0.5*0.7 + 0.3*0.8 + 0.2*0.2, // 0.35 + 0.24 + 0.04 = 0.63
			wantErr:   false,
		},
		{
			name: "invalid weights sum",
			weights: malev1alpha1.Weights{
				Accuracy: 0.5,
				Latency:  0.3,
				Energy:   0.1, // Sum = 0.9, not 1.0
			},
			importance: malev1alpha1.ImportanceValues{
				Accuracy: 0.7,
				Latency:  0.8,
				Energy:   0.2,
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			score, err := CalculateMixedScore(tt.weights, tt.importance)
			if (err != nil) != tt.wantErr {
				t.Errorf("CalculateMixedScore() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if !tt.wantErr && score != tt.wantScore {
				t.Errorf("CalculateMixedScore() = %v, want %v", score, tt.wantScore)
			}
		})
	}
}

func TestClampValues(t *testing.T) {
	bounds := malev1alpha1.Bounds{
		Accuracy: malev1alpha1.MinMax{Min: 0.0, Max: 1.0},
		Latency:  malev1alpha1.MinMax{Min: 0.0, Max: 0.9},
		Energy:   malev1alpha1.MinMax{Min: 0.1, Max: 1.0},
	}

	importance := malev1alpha1.ImportanceValues{
		Accuracy: 1.5,  // Should be clamped to 1.0
		Latency:  0.5,  // Should remain 0.5
		Energy:   0.05, // Should be clamped to 0.1
	}

	result := ClampValues(importance, bounds)

	if result.Accuracy != 1.0 {
		t.Errorf("ClampValues() Accuracy = %v, want 1.0", result.Accuracy)
	}
	if result.Latency != 0.5 {
		t.Errorf("ClampValues() Latency = %v, want 0.5", result.Latency)
	}
	if result.Energy != 0.1 {
		t.Errorf("ClampValues() Energy = %v, want 0.1", result.Energy)
	}
}

func TestFindPriorityBucket(t *testing.T) {
	buckets := []malev1alpha1.PriorityBucket{
		{Name: "low", Min: 0.0, Max: 0.29, PriorityValue: 100},
		{Name: "medium", Min: 0.30, Max: 0.59, PriorityValue: 1000},
		{Name: "high", Min: 0.60, Max: 0.79, PriorityValue: 10000},
		{Name: "critical", Min: 0.80, Max: 1.0, PriorityValue: 100000},
	}

	tests := []struct {
		name     string
		score    float64
		wantName string
		wantErr  bool
	}{
		{"low score", 0.15, "low", false},
		{"medium score", 0.45, "medium", false},
		{"high score", 0.70, "high", false},
		{"critical score", 0.90, "critical", false},
		{"no match", 1.5, "", true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			bucket, err := FindPriorityBucket(tt.score, buckets)
			if (err != nil) != tt.wantErr {
				t.Errorf("FindPriorityBucket() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if !tt.wantErr && bucket.Name != tt.wantName {
				t.Errorf("FindPriorityBucket() = %v, want %v", bucket.Name, tt.wantName)
			}
		})
	}
}

func TestValidateWeights(t *testing.T) {
	tests := []struct {
		name    string
		weights malev1alpha1.Weights
		wantErr bool
	}{
		{"valid", malev1alpha1.Weights{Accuracy: 0.5, Latency: 0.3, Energy: 0.2}, false},
		{"invalid sum", malev1alpha1.Weights{Accuracy: 0.5, Latency: 0.3, Energy: 0.1}, true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if err := ValidateWeights(tt.weights); (err != nil) != tt.wantErr {
				t.Errorf("ValidateWeights() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}

func TestValidatePriorityBuckets(t *testing.T) {
	tests := []struct {
		name    string
		buckets []malev1alpha1.PriorityBucket
		wantErr bool
	}{
		{
			name: "valid non-overlapping",
			buckets: []malev1alpha1.PriorityBucket{
				{Name: "low", Min: 0.0, Max: 0.29},
				{Name: "medium", Min: 0.30, Max: 0.59},
			},
			wantErr: false,
		},
		{
			name: "overlapping buckets",
			buckets: []malev1alpha1.PriorityBucket{
				{Name: "low", Min: 0.0, Max: 0.40},
				{Name: "medium", Min: 0.30, Max: 0.59}, // Overlaps with low
			},
			wantErr: true,
		},
		{
			name:    "empty buckets",
			buckets: []malev1alpha1.PriorityBucket{},
			wantErr: true,
		},
		{
			name: "invalid range",
			buckets: []malev1alpha1.PriorityBucket{
				{Name: "invalid", Min: 1.5, Max: 2.0}, // Out of [0,1]
			},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if err := ValidatePriorityBuckets(tt.buckets); (err != nil) != tt.wantErr {
				t.Errorf("ValidatePriorityBuckets() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}
