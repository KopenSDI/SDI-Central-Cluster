package sdi

import (
	"context"
	"math"
	"strconv"

	clusterv1alpha1 "github.com/karmada-io/karmada/pkg/apis/cluster/v1alpha1"
	workv1alpha2 "github.com/karmada-io/karmada/pkg/apis/work/v1alpha2"
	"github.com/karmada-io/karmada/pkg/scheduler/framework"
)

type PredictiveContext struct{}

func (p *PredictiveContext) Name() string { return "PredictiveContext" }

func (p *PredictiveContext) Filter(_ context.Context,
	_ *workv1alpha2.ResourceBindingSpec,
	cl *clusterv1alpha1.Cluster,
	ale *ALE) framework.Code {

	powerW := 0
	if v, ok := cl.Labels["est.power.watt"]; ok {
		if iv, err := strconv.Atoi(v); err == nil {
			powerW = iv
		}
	}
	if ale.Energy.PowerBudgetWatt > 0 && powerW+ale.Energy.PowerBudgetWatt > 350 {
		return framework.Unschedulable
	}

	batteryPct := 100
	if v, ok := cl.Labels["battery-pct"]; ok {
		if iv, err := strconv.Atoi(v); err == nil {
			batteryPct = iv
		}
	}
	batteryThreshold := 30
	if batteryPct < batteryThreshold {
		return framework.Unschedulable
	}

	return framework.Success
}

func (p *PredictiveContext) Score(_ context.Context,
	_ *workv1alpha2.ResourceBindingSpec,
	cl *clusterv1alpha1.Cluster,
	ale *ALE) (int64, error) {

	cu := 0.0
	mu := 0.0
	if v, ok := cl.Labels["est.cpu.usage"]; ok {
		if f, err := strconv.ParseFloat(v, 64); err == nil {
			cu = f
		}
	}
	if v, ok := cl.Labels["est.mem.usage"]; ok {
		if f, err := strconv.ParseFloat(v, 64); err == nil {
			mu = f
		}
	}

	batteryPct := 100.0
	if v, ok := cl.Labels["battery-pct"]; ok {
		if f, err := strconv.ParseFloat(v, 64); err == nil {
			batteryPct = f / 100.0
		}
	}

	resourceFree := 1 - math.Max(cu, mu)
	if resourceFree < 0 {
		resourceFree = 0
	}

	score := int64(math.Round(resourceFree*400 + batteryPct*600))
	if score > 1000 {
		score = 1000
	}

	return score, nil
}
