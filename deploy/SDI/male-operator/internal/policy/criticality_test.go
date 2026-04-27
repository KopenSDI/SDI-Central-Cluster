/*
Copyright 2024 KETI.

Licensed under the Apache License, Version 2.0 (the "License");
*/

package policy

import (
	"testing"

	malev1alpha1 "github.com/keti-lab/male-operator/api/v1alpha1"
)

// TestDetermineCriticality_MALEPaperCases tests the three industrial cases from the MALE paper
func TestDetermineCriticality_MALEPaperCases(t *testing.T) {
	tests := []struct {
		name                string
		importance          malev1alpha1.ImportanceValues
		expectedCriticality CriticalityLevel
		expectedMissionType MissionType
		description         string
	}{
		{
			name: "Autonomous Vehicles (Accuracy-Critical)",
			importance: malev1alpha1.ImportanceValues{
				Accuracy: 0.6,
				Latency:  0.3,
				Energy:   0.1,
			},
			expectedCriticality: CriticalityC,
			expectedMissionType: MissionTypeAccuracyCritical,
			description:         "MALE Paper: Autonomous Vehicles require high accuracy for safety (A=0.6, L=0.3, E=0.1)",
		},
		{
			name: "Real-Time Robotics (Latency-Critical)",
			importance: malev1alpha1.ImportanceValues{
				Accuracy: 0.1,
				Latency:  0.7,
				Energy:   0.2,
			},
			expectedCriticality: CriticalityB,
			expectedMissionType: MissionTypeLatencyCritical,
			description:         "MALE Paper: Real-Time Robotics require low latency (A=0.1, L=0.7, E=0.2)",
		},
		{
			name: "IoT Sensor Networks (Energy-Critical)",
			importance: malev1alpha1.ImportanceValues{
				Accuracy: 0.2,
				Latency:  0.1,
				Energy:   0.7,
			},
			expectedCriticality: CriticalityA,
			expectedMissionType: MissionTypeEnergyCritical,
			description:         "MALE Paper: IoT Sensors prioritize energy efficiency (A=0.2, L=0.1, E=0.7)",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := DetermineCriticality(tt.importance, "", true)

			if result.MissionType != tt.expectedMissionType {
				t.Errorf("MissionType = %v, want %v\nDescription: %s",
					result.MissionType, tt.expectedMissionType, tt.description)
			}

			if result.Criticality != tt.expectedCriticality {
				t.Errorf("Criticality = %v, want %v\nReason: %s\nDescription: %s",
					result.Criticality, tt.expectedCriticality, result.Reason, tt.description)
			}
		})
	}
}

// TestDetermineCriticality_SafetyCritical tests Safety-Critical (C) scenarios
func TestDetermineCriticality_SafetyCritical(t *testing.T) {
	tests := []struct {
		name       string
		importance malev1alpha1.ImportanceValues
	}{
		{
			name: "Very high latency (0.9)",
			importance: malev1alpha1.ImportanceValues{
				Accuracy: 0.3,
				Latency:  0.9,
				Energy:   0.1,
			},
		},
		{
			name: "High latency + moderate accuracy",
			importance: malev1alpha1.ImportanceValues{
				Accuracy: 0.5,
				Latency:  0.7,
				Energy:   0.1,
			},
		},
		{
			name: "High accuracy + moderate latency",
			importance: malev1alpha1.ImportanceValues{
				Accuracy: 0.7,
				Latency:  0.4,
				Energy:   0.1,
			},
		},
		{
			name: "Combined A+L >= 0.9",
			importance: malev1alpha1.ImportanceValues{
				Accuracy: 0.5,
				Latency:  0.5,
				Energy:   0.1,
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := DetermineCriticality(tt.importance, "", true)

			if result.Criticality != CriticalityC {
				t.Errorf("Expected Criticality C (Safety-Critical), got %v\nReason: %s",
					result.Criticality, result.Reason)
			}
		})
	}
}

// TestDetermineCriticality_BestEffort tests Best-Effort (A) scenarios
func TestDetermineCriticality_BestEffort(t *testing.T) {
	tests := []struct {
		name       string
		importance malev1alpha1.ImportanceValues
	}{
		{
			name: "Energy-dominant with low latency",
			importance: malev1alpha1.ImportanceValues{
				Accuracy: 0.2,
				Latency:  0.1,
				Energy:   0.8,
			},
		},
		{
			name: "All low values",
			importance: malev1alpha1.ImportanceValues{
				Accuracy: 0.2,
				Latency:  0.2,
				Energy:   0.2,
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := DetermineCriticality(tt.importance, "", true)

			if result.Criticality != CriticalityA {
				t.Errorf("Expected Criticality A (Best-Effort), got %v\nReason: %s",
					result.Criticality, result.Reason)
			}
		})
	}
}

// TestDetermineCriticality_Override tests override behavior
func TestDetermineCriticality_Override(t *testing.T) {
	importance := malev1alpha1.ImportanceValues{
		Accuracy: 0.6,
		Latency:  0.3,
		Energy:   0.1,
	}

	t.Run("Override enabled - changes user value", func(t *testing.T) {
		result := DetermineCriticality(importance, "A", true)

		if result.Criticality != CriticalityC {
			t.Errorf("Expected override to C, got %v", result.Criticality)
		}
		if !result.WasOverridden {
			t.Error("Expected WasOverridden to be true")
		}
	})

	t.Run("Override disabled - keeps user value", func(t *testing.T) {
		result := DetermineCriticality(importance, "A", false)

		if result.Criticality != CriticalityA {
			t.Errorf("Expected to keep user value A, got %v", result.Criticality)
		}
		if result.WasOverridden {
			t.Error("Expected WasOverridden to be false when override disabled")
		}
	})

	t.Run("User value matches calculated - no override", func(t *testing.T) {
		result := DetermineCriticality(importance, "C", true)

		if result.WasOverridden {
			t.Error("Expected WasOverridden to be false when values match")
		}
	})
}

// TestDetectMissionType tests mission type detection
func TestDetectMissionType(t *testing.T) {
	thresholds := DefaultCriticalityThresholds()

	tests := []struct {
		name       string
		importance malev1alpha1.ImportanceValues
		expected   MissionType
	}{
		{
			name: "Clear latency-critical",
			importance: malev1alpha1.ImportanceValues{
				Accuracy: 0.1,
				Latency:  0.8,
				Energy:   0.1,
			},
			expected: MissionTypeLatencyCritical,
		},
		{
			name: "Clear accuracy-critical",
			importance: malev1alpha1.ImportanceValues{
				Accuracy: 0.8,
				Latency:  0.1,
				Energy:   0.1,
			},
			expected: MissionTypeAccuracyCritical,
		},
		{
			name: "Clear energy-critical",
			importance: malev1alpha1.ImportanceValues{
				Accuracy: 0.1,
				Latency:  0.1,
				Energy:   0.8,
			},
			expected: MissionTypeEnergyCritical,
		},
		{
			name: "Balanced",
			importance: malev1alpha1.ImportanceValues{
				Accuracy: 0.4,
				Latency:  0.4,
				Energy:   0.4,
			},
			expected: MissionTypeBalanced,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := DetectMissionType(tt.importance, thresholds)
			if result != tt.expected {
				t.Errorf("DetectMissionType() = %v, want %v", result, tt.expected)
			}
		})
	}
}

// TestCompareCriticality tests criticality comparison
func TestCompareCriticality(t *testing.T) {
	tests := []struct {
		a, b     CriticalityLevel
		expected int
	}{
		{CriticalityA, CriticalityB, -1},
		{CriticalityB, CriticalityA, 1},
		{CriticalityB, CriticalityC, -1},
		{CriticalityC, CriticalityB, 1},
		{CriticalityA, CriticalityA, 0},
		{CriticalityC, CriticalityC, 0},
	}

	for _, tt := range tests {
		t.Run(string(tt.a)+"_vs_"+string(tt.b), func(t *testing.T) {
			result := CompareCriticality(tt.a, tt.b)
			if result != tt.expected {
				t.Errorf("CompareCriticality(%v, %v) = %v, want %v",
					tt.a, tt.b, result, tt.expected)
			}
		})
	}
}
