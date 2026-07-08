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
	"fmt"
	"math"

	malev1alpha1 "github.com/keti-lab/male-operator/api/v1alpha1"
)

// CalculateMixedScore calculates the mixed importance score using the formula:
// MixedImportance = wA*A + wL*L + wE*E
// where wA, wL, wE are weights and A, L, E are importance values (all in [0,1])
func CalculateMixedScore(weights malev1alpha1.Weights, importance malev1alpha1.ImportanceValues) (float64, error) {
	// Validate weights sum to 1.0 (with small tolerance for floating point)
	sum := weights.Accuracy + weights.Latency + weights.Energy
	if math.Abs(sum-1.0) > 0.001 {
		return 0, fmt.Errorf("weights must sum to 1.0, got %.3f", sum)
	}

	score := weights.Accuracy*importance.Accuracy +
		weights.Latency*importance.Latency +
		weights.Energy*importance.Energy

	// Clamp to [0,1]
	score = math.Max(0.0, math.Min(1.0, score))

	return score, nil
}

// ClampValues clamps importance values to the specified bounds
func ClampValues(importance malev1alpha1.ImportanceValues, bounds malev1alpha1.Bounds) malev1alpha1.ImportanceValues {
	return malev1alpha1.ImportanceValues{
		Accuracy: math.Max(bounds.Accuracy.Min, math.Min(bounds.Accuracy.Max, importance.Accuracy)),
		Latency:  math.Max(bounds.Latency.Min, math.Min(bounds.Latency.Max, importance.Latency)),
		Energy:   math.Max(bounds.Energy.Min, math.Min(bounds.Energy.Max, importance.Energy)),
	}
}

// FindPriorityBucket finds the priority bucket for a given score
func FindPriorityBucket(score float64, buckets []malev1alpha1.PriorityBucket) (*malev1alpha1.PriorityBucket, error) {
	for i := range buckets {
		bucket := buckets[i]
		if score >= bucket.Min && score <= bucket.Max {
			return &bucket, nil
		}
	}
	return nil, fmt.Errorf("score %.3f does not match any priority bucket", score)
}

// ValidateWeights validates that weights sum to 1.0
func ValidateWeights(weights malev1alpha1.Weights) error {
	sum := weights.Accuracy + weights.Latency + weights.Energy
	if math.Abs(sum-1.0) > 0.001 {
		return fmt.Errorf("weights must sum to 1.0, got %.3f (accuracy=%.3f, latency=%.3f, energy=%.3f)",
			sum, weights.Accuracy, weights.Latency, weights.Energy)
	}
	return nil
}

// ValidatePriorityBuckets validates that priority buckets are non-overlapping and cover [0,1]
func ValidatePriorityBuckets(buckets []malev1alpha1.PriorityBucket) error {
	if len(buckets) == 0 {
		return fmt.Errorf("at least one priority bucket is required")
	}

	// Check for overlaps and gaps
	for i := range buckets {
		bucket := buckets[i]
		if bucket.Min < 0 || bucket.Max > 1 {
			return fmt.Errorf("bucket %s: min and max must be in [0,1], got [%.3f, %.3f]",
				bucket.Name, bucket.Min, bucket.Max)
		}
		if bucket.Min > bucket.Max {
			return fmt.Errorf("bucket %s: min (%.3f) must be <= max (%.3f)",
				bucket.Name, bucket.Min, bucket.Max)
		}

		// Check for overlaps with other buckets
		for j := i + 1; j < len(buckets); j++ {
			other := buckets[j]
			if bucket.Min <= other.Max && bucket.Max >= other.Min {
				return fmt.Errorf("buckets %s and %s overlap: [%.3f, %.3f] vs [%.3f, %.3f]",
					bucket.Name, other.Name, bucket.Min, bucket.Max, other.Min, other.Max)
			}
		}
	}

	return nil
}
