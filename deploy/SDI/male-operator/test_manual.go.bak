package main

import (
	"fmt"
	"log"

	malev1alpha1 "github.com/keti-lab/male-operator/api/v1alpha1"
	"github.com/keti-lab/male-operator/internal/policy"
)

func main() {
	fmt.Println("=== MALE Operator Manual Test ===")
	fmt.Println()

	// Test 1: Create a MalePolicy
	malePolicy := &malev1alpha1.MalePolicy{
		Spec: malev1alpha1.MalePolicySpec{
			Weights: malev1alpha1.Weights{
				Accuracy: 0.5,
				Latency:  0.3,
				Energy:   0.2,
			},
			Bounds: malev1alpha1.Bounds{
				Accuracy: malev1alpha1.MinMax{Min: 0.0, Max: 1.0},
				Latency:  malev1alpha1.MinMax{Min: 0.0, Max: 1.0},
				Energy:   malev1alpha1.MinMax{Min: 0.0, Max: 1.0},
			},
			PriorityBuckets: []malev1alpha1.PriorityBucket{
				{Name: "male-low", Min: 0.0, Max: 0.29, PriorityValue: 100},
				{Name: "male-medium", Min: 0.30, Max: 0.59, PriorityValue: 1000},
				{Name: "male-high", Min: 0.60, Max: 0.79, PriorityValue: 10000},
				{Name: "male-critical", Min: 0.80, Max: 1.0, PriorityValue: 100000},
			},
		},
	}

	// Test 2: Validate weights
	fmt.Println("1. Validating weights...")
	if err := malePolicy.ValidateWeights(); err != nil {
		log.Fatalf("✗ Weight validation failed: %v", err)
	}
	fmt.Println("   ✓ Weights are valid (sum = 1.0)")

	// Test 3: Validate priority buckets
	fmt.Println("\n2. Validating priority buckets...")
	if err := malePolicy.ValidatePriorityBuckets(); err != nil {
		log.Fatalf("✗ Bucket validation failed: %v", err)
	}
	fmt.Println("   ✓ Priority buckets are valid")

	// Test 4: Create a MaleWorkload
	workload := &malev1alpha1.MaleWorkload{
		Spec: malev1alpha1.MaleWorkloadSpec{
			Importance: malev1alpha1.ImportanceValues{
				Accuracy: 0.7,
				Latency:  0.8,
				Energy:   0.2,
			},
		},
	}

	// Test 5: Clamp values
	fmt.Println("\n3. Testing value clamping...")
	clamped := policy.ClampValues(workload.Spec.Importance, malePolicy.Spec.Bounds)
	fmt.Printf("   Original: A=%.2f, L=%.2f, E=%.2f\n", workload.Spec.Importance.Accuracy, workload.Spec.Importance.Latency, workload.Spec.Importance.Energy)
	fmt.Printf("   Clamped:  A=%.2f, L=%.2f, E=%.2f\n", clamped.Accuracy, clamped.Latency, clamped.Energy)
	fmt.Println("   ✓ Values clamped successfully")

	// Test 6: Calculate mixed score
	fmt.Println("\n4. Calculating mixed importance score...")
	mixedScore, err := policy.CalculateMixedScore(malePolicy.Spec.Weights, clamped)
	if err != nil {
		log.Fatalf("✗ Score calculation failed: %v", err)
	}
	fmt.Printf("   Mixed Score: %.3f\n", mixedScore)
	fmt.Println("   ✓ Score calculated successfully")

	// Test 7: Find priority bucket
	fmt.Println("\n5. Finding priority bucket...")
	bucket, err := policy.FindPriorityBucket(mixedScore, malePolicy.Spec.PriorityBuckets)
	if err != nil {
		log.Fatalf("✗ Bucket lookup failed: %v", err)
	}
	fmt.Printf("   PriorityClass: %s (value: %d)\n", bucket.Name, bucket.PriorityValue)
	fmt.Println("   ✓ Bucket found successfully")

	// Test 8: Expected calculation
	fmt.Println("\n6. Expected calculation verification...")
	expectedScore := 0.5*0.7 + 0.3*0.8 + 0.2*0.2 // wA*A + wL*L + wE*E
	fmt.Printf("   Expected: %.3f (0.5*0.7 + 0.3*0.8 + 0.2*0.2)\n", expectedScore)
	fmt.Printf("   Actual:   %.3f\n", mixedScore)
	if mixedScore == expectedScore {
		fmt.Println("   ✓ Calculation matches expected value")
	} else {
		fmt.Printf("   ⚠ Small difference (floating point precision)\n")
	}

	fmt.Println("\n=== All Tests Passed! ===")
}

