/*
MALE MC Criticality 재정의 데모

데이터 플로우:

	[입력] MaleWorkload YAML
	       ↓
	[처리] DetermineCriticality (ALE 분석)
	       ↓
	[출력] EffectiveMCSpec (재정의된 criticality)
*/
package main

import (
	"fmt"

	malev1alpha1 "github.com/keti-lab/male-operator/api/v1alpha1"
	"github.com/keti-lab/male-operator/internal/policy"
)

func main() {
	fmt.Println("============================================================")
	fmt.Println(" MALE MC Criticality 재정의 데모")
	fmt.Println("============================================================")
	fmt.Println()
	fmt.Println("MALE 논문 기반 재정의 규칙:")
	fmt.Println("  - L >= 0.9                → C (Safety-Critical)")
	fmt.Println("  - L >= 0.7 && A >= 0.5    → C (Safety-Critical)")
	fmt.Println("  - A >= 0.6 && L >= 0.3    → C (자율주행 패턴)")
	fmt.Println("  - A + L >= 0.9            → C (결합 임계값)")
	fmt.Println("  - L >= 0.5                → B (Mission-Critical)")
	fmt.Println("  - E >= 0.5 && L < 0.5     → A (Energy-Critical)")
	fmt.Println()

	testCases := []struct {
		name            string
		accuracy        float64
		latency         float64
		energy          float64
		userCriticality string
		expectedCrit    string
		expectedMission string
	}{
		{
			name:            "자율주행 (Autonomous Vehicles)",
			accuracy:        0.6,
			latency:         0.3,
			energy:          0.1,
			userCriticality: "A",
			expectedCrit:    "C",
			expectedMission: "accuracy-critical",
		},
		{
			name:            "실시간 로봇 (Real-Time Robotics)",
			accuracy:        0.1,
			latency:         0.7,
			energy:          0.2,
			userCriticality: "A",
			expectedCrit:    "B",
			expectedMission: "latency-critical",
		},
		{
			name:            "IoT 센서 (IoT Sensors)",
			accuracy:        0.2,
			latency:         0.1,
			energy:          0.7,
			userCriticality: "C",
			expectedCrit:    "A",
			expectedMission: "energy-critical",
		},
		{
			name:            "고위험 로봇 (High-Risk Robot)",
			accuracy:        0.5,
			latency:         0.9,
			energy:          0.1,
			userCriticality: "B",
			expectedCrit:    "C",
			expectedMission: "latency-critical",
		},
	}

	for i, tc := range testCases {
		fmt.Printf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
		fmt.Printf("테스트 %d: %s\n", i+1, tc.name)
		fmt.Printf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

		// 입력
		importance := malev1alpha1.ImportanceValues{
			Accuracy: tc.accuracy,
			Latency:  tc.latency,
			Energy:   tc.energy,
		}

		fmt.Println()
		fmt.Println("[입력] spec.importance:")
		fmt.Printf("  accuracy: %.1f\n", tc.accuracy)
		fmt.Printf("  latency:  %.1f\n", tc.latency)
		fmt.Printf("  energy:   %.1f\n", tc.energy)
		fmt.Println()
		fmt.Printf("[입력] spec.mcSpec.criticality: %s (사용자 지정)\n", tc.userCriticality)
		fmt.Println()

		// 처리
		result := policy.DetermineCriticality(importance, tc.userCriticality, true)

		// 출력
		fmt.Println("[출력] status.effectiveMcSpec:")
		fmt.Printf("  criticality:    %s\n", result.Criticality)
		fmt.Printf("  missionType:    %s\n", result.MissionType)
		if result.WasOverridden {
			fmt.Printf("  overrideReason: %s\n", result.Reason)
			fmt.Printf("  wasOverridden:  true (원래값: %s)\n", result.OriginalCriticality)
		} else {
			fmt.Printf("  wasOverridden:  false\n")
		}
		fmt.Println()

		// 검증
		status := "✓ PASS"
		if string(result.Criticality) != tc.expectedCrit {
			status = fmt.Sprintf("✗ FAIL (expected %s)", tc.expectedCrit)
		}
		fmt.Printf("[검증] %s\n", status)
		fmt.Println()
	}

	fmt.Println("============================================================")
	fmt.Println(" 데모 완료")
	fmt.Println("============================================================")
}
