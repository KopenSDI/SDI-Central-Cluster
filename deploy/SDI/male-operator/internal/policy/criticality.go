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
	malev1alpha1 "github.com/keti-lab/male-operator/api/v1alpha1"
)

// ============================================================
// MALE Paper-based Criticality Determination
// ============================================================
// Reference: "MALE: A Multi-Objective Evaluation Method for
//            AI Mobility Services across the Cloud-Edge-Device Continuum"
//
// Mission Types from Paper (Section IV):
// - Autonomous Vehicles: A=0.6, L=0.3, E=0.1 (Accuracy-Critical)
// - Real-Time Robotics:  A=0.1, L=0.7, E=0.2 (Latency-Critical)
// - IoT Sensor Networks: A=0.2, L=0.1, E=0.7 (Energy-Critical)
//
// Criticality Levels (RT-Kube MC Scheduling):
// - C: Safety-Critical    (collision avoidance, robot arm control)
// - B: Mission-Critical   (SLAM, sensor processing)
// - A: Best-Effort RT     (logging, monitoring)
// ============================================================

// MissionType represents the detected mission category based on ALE importance
type MissionType string

const (
	// MissionTypeAccuracyCritical - High accuracy requirement (e.g., autonomous vehicles)
	MissionTypeAccuracyCritical MissionType = "accuracy-critical"

	// MissionTypeLatencyCritical - High latency requirement (e.g., real-time robotics)
	MissionTypeLatencyCritical MissionType = "latency-critical"

	// MissionTypeEnergyCritical - High energy efficiency requirement (e.g., IoT sensors)
	MissionTypeEnergyCritical MissionType = "energy-critical"

	// MissionTypeBalanced - No dominant criterion
	MissionTypeBalanced MissionType = "balanced"
)

// CriticalityLevel represents MC criticality
type CriticalityLevel string

const (
	CriticalityA CriticalityLevel = "A" // Best-Effort RT
	CriticalityB CriticalityLevel = "B" // Mission-Critical
	CriticalityC CriticalityLevel = "C" // Safety-Critical
)

// CriticalityThresholds defines thresholds for criticality determination
// These are derived from the MALE paper's case studies
type CriticalityThresholds struct {
	// LatencyCriticalThreshold: >= this value indicates latency-critical mission
	// Based on Real-Time Robotics case: L=0.7
	LatencyCriticalThreshold float64

	// AccuracyCriticalThreshold: >= this value indicates accuracy-critical mission
	// Based on Autonomous Vehicles case: A=0.6
	AccuracyCriticalThreshold float64

	// EnergyCriticalThreshold: >= this value indicates energy-critical mission
	// Based on IoT Sensor Networks case: E=0.7
	EnergyCriticalThreshold float64

	// SafetyCriticalLatencyThreshold: Very high latency requirement -> Safety-Critical
	SafetyCriticalLatencyThreshold float64

	// SafetyCriticalCombinedThreshold: Combined A+L threshold for Safety-Critical
	SafetyCriticalCombinedThreshold float64
}

// DefaultCriticalityThresholds returns default thresholds based on MALE paper
func DefaultCriticalityThresholds() CriticalityThresholds {
	return CriticalityThresholds{
		LatencyCriticalThreshold:        0.7, // Real-Time Robotics: L=0.7
		AccuracyCriticalThreshold:       0.6, // Autonomous Vehicles: A=0.6
		EnergyCriticalThreshold:         0.7, // IoT Sensors: E=0.7
		SafetyCriticalLatencyThreshold:  0.9, // Very high latency -> C
		SafetyCriticalCombinedThreshold: 0.9, // A + L >= 0.9 -> C
	}
}

// CriticalityResult contains the determined criticality and reasoning
type CriticalityResult struct {
	// Criticality is the determined MC level (A, B, or C)
	Criticality CriticalityLevel

	// MissionType is the detected mission category
	MissionType MissionType

	// Reason explains why this criticality was determined
	Reason string

	// WasOverridden indicates if user-specified criticality was changed
	WasOverridden bool

	// OriginalCriticality is the user-specified value (if overridden)
	OriginalCriticality string
}

// DetermineCriticality determines the appropriate MC criticality level
// based on the MALE paper's mission-driven ALE evaluation method.
//
// The algorithm analyzes the ALE importance values to detect the mission type,
// then maps it to the appropriate criticality level for RT-Kube MC scheduling.
//
// Parameters:
//   - importance: User-specified ALE importance values (each in [0,1])
//   - userCriticality: User-specified criticality (may be overridden)
//   - allowOverride: Whether the operator can override user's criticality
//
// Returns:
//   - CriticalityResult containing the final criticality and reasoning
func DetermineCriticality(
	importance malev1alpha1.ImportanceValues,
	userCriticality string,
	allowOverride bool,
) CriticalityResult {
	thresholds := DefaultCriticalityThresholds()
	return DetermineCriticalityWithThresholds(importance, userCriticality, allowOverride, thresholds)
}

// DetermineCriticalityWithThresholds allows custom thresholds for testing
func DetermineCriticalityWithThresholds(
	importance malev1alpha1.ImportanceValues,
	userCriticality string,
	allowOverride bool,
	thresholds CriticalityThresholds,
) CriticalityResult {
	result := CriticalityResult{
		OriginalCriticality: userCriticality,
		WasOverridden:       false,
	}

	// Detect mission type from ALE importance values
	missionType := DetectMissionType(importance, thresholds)
	result.MissionType = missionType

	// Determine criticality based on mission type and importance values
	criticality, reason := determineCriticalityFromImportance(importance, missionType, thresholds)
	result.Criticality = criticality
	result.Reason = reason

	// Check if we should override user's criticality
	if !allowOverride && userCriticality != "" {
		// User doesn't allow override, use their value
		result.Criticality = CriticalityLevel(userCriticality)
		result.Reason = "User-specified criticality (override disabled)"
		return result
	}

	// Check if user's criticality differs from calculated
	if userCriticality != "" && userCriticality != string(criticality) {
		result.WasOverridden = true
		result.Reason = result.Reason + " [Overridden from " + userCriticality + "]"
	}

	return result
}

// DetectMissionType analyzes ALE importance values to detect the mission category
// Based on MALE paper Section III-A-1: "Defining mission based on ALE"
func DetectMissionType(importance malev1alpha1.ImportanceValues, thresholds CriticalityThresholds) MissionType {
	A := importance.Accuracy
	L := importance.Latency
	E := importance.Energy

	// Find the dominant criterion
	// A criterion is dominant if it's significantly higher than others

	// Latency-critical: L is dominant (e.g., Real-Time Robotics: L=0.7)
	if L >= thresholds.LatencyCriticalThreshold && L > A && L > E {
		return MissionTypeLatencyCritical
	}

	// Accuracy-critical: A is dominant (e.g., Autonomous Vehicles: A=0.6)
	if A >= thresholds.AccuracyCriticalThreshold && A > L && A > E {
		return MissionTypeAccuracyCritical
	}

	// Energy-critical: E is dominant (e.g., IoT Sensors: E=0.7)
	if E >= thresholds.EnergyCriticalThreshold && E > A && E > L {
		return MissionTypeEnergyCritical
	}

	// Special case: Autonomous Vehicles pattern (high A, moderate L)
	// Paper: A=0.6, L=0.3, E=0.1
	if A >= 0.5 && L >= 0.2 && E < 0.3 {
		return MissionTypeAccuracyCritical
	}

	// Special case: Real-Time Robotics pattern (very high L)
	// Paper: A=0.1, L=0.7, E=0.2
	if L >= 0.6 && A < 0.3 {
		return MissionTypeLatencyCritical
	}

	// Special case: IoT Sensors pattern (high E, low L)
	// Paper: A=0.2, L=0.1, E=0.7
	if E >= 0.5 && L < 0.3 {
		return MissionTypeEnergyCritical
	}

	return MissionTypeBalanced
}

// determineCriticalityFromImportance maps mission type and importance to criticality
func determineCriticalityFromImportance(
	importance malev1alpha1.ImportanceValues,
	missionType MissionType,
	thresholds CriticalityThresholds,
) (CriticalityLevel, string) {
	A := importance.Accuracy
	L := importance.Latency

	// ============================================================
	// Rule 1: Very high latency requirement -> Safety-Critical (C)
	// Example: Ultra-low-latency robotics (Boston Dynamics Spot: 300ms)
	// ============================================================
	if L >= thresholds.SafetyCriticalLatencyThreshold {
		return CriticalityC, "Very high latency importance (>=0.9) requires safety-critical RT scheduling"
	}

	// ============================================================
	// Rule 2: High latency + moderate accuracy -> Safety-Critical (C)
	// This combination indicates safety-critical real-time systems
	// Example: Autonomous vehicle perception + control
	// ============================================================
	if L >= 0.7 && A >= 0.5 {
		return CriticalityC, "High latency (>=0.7) with moderate accuracy (>=0.5) indicates safety-critical workload"
	}

	// ============================================================
	// Rule 3: High accuracy + moderate latency -> Safety-Critical (C)
	// Based on Autonomous Vehicles case: A=0.6, L=0.3
	// Safety-critical systems need accurate decisions with timely response
	// ============================================================
	if A >= 0.6 && L >= 0.3 {
		return CriticalityC, "Accuracy-critical mission with moderate latency (Autonomous Vehicles pattern: A>=0.6, L>=0.3)"
	}

	// ============================================================
	// Rule 4: Combined threshold for Safety-Critical
	// If A + L is very high, the workload is likely safety-critical
	// ============================================================
	if A+L >= thresholds.SafetyCriticalCombinedThreshold {
		return CriticalityC, "Combined accuracy+latency importance (>=0.9) indicates safety-critical workload"
	}

	// ============================================================
	// Mission-type based determination for B and A levels
	// ============================================================
	switch missionType {
	case MissionTypeLatencyCritical:
		// High latency but not meeting C threshold -> Mission-Critical (B)
		// Example: SLAM processing, sensor fusion
		if L >= 0.5 {
			return CriticalityB, "Latency-critical mission (Real-Time Robotics pattern) -> Mission-Critical"
		}
		return CriticalityB, "Latency-critical mission detected -> Mission-Critical"

	case MissionTypeAccuracyCritical:
		// High accuracy but not meeting C threshold -> Mission-Critical (B)
		if A >= 0.5 {
			return CriticalityB, "Accuracy-critical mission with moderate requirements -> Mission-Critical"
		}
		return CriticalityB, "Accuracy-critical mission detected -> Mission-Critical"

	case MissionTypeEnergyCritical:
		// Energy-critical missions typically have relaxed latency requirements
		// Based on IoT Sensors case: A=0.2, L=0.1, E=0.7
		// These can tolerate deadline misses -> Best-Effort (A)
		return CriticalityA, "Energy-critical mission (IoT Sensors pattern) with relaxed latency -> Best-Effort RT"

	case MissionTypeBalanced:
		// Balanced workload: determine based on absolute values
		if L >= 0.5 || A >= 0.5 {
			return CriticalityB, "Balanced mission with moderate importance -> Mission-Critical"
		}
		return CriticalityA, "Balanced mission with low criticality requirements -> Best-Effort RT"
	}

	// Default: Best-Effort
	return CriticalityA, "Default best-effort scheduling for unclassified workload"
}

// ValidateCriticality checks if a criticality string is valid
func ValidateCriticality(criticality string) bool {
	switch criticality {
	case "A", "B", "C":
		return true
	default:
		return false
	}
}

// CompareCriticality returns:
//
//	-1 if a < b (a is lower priority)
//	 0 if a == b
//	 1 if a > b (a is higher priority)
//
// Criticality order: C > B > A
func CompareCriticality(a, b CriticalityLevel) int {
	order := map[CriticalityLevel]int{
		CriticalityA: 0,
		CriticalityB: 1,
		CriticalityC: 2,
	}

	if order[a] < order[b] {
		return -1
	} else if order[a] > order[b] {
		return 1
	}
	return 0
}
