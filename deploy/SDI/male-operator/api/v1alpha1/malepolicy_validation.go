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
	"fmt"
	"math"
)

// ValidateWeights validates that weights sum to 1.0
func (p *MalePolicy) ValidateWeights() error {
	sum := p.Spec.Weights.Accuracy + p.Spec.Weights.Latency + p.Spec.Weights.Energy
	if math.Abs(sum-1.0) > 0.001 {
		return fmt.Errorf("weights must sum to 1.0, got %.3f (accuracy=%.3f, latency=%.3f, energy=%.3f)",
			sum, p.Spec.Weights.Accuracy, p.Spec.Weights.Latency, p.Spec.Weights.Energy)
	}
	return nil
}

// ValidatePriorityBuckets validates that priority buckets are non-overlapping
func (p *MalePolicy) ValidatePriorityBuckets() error {
	buckets := p.Spec.PriorityBuckets
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
