package sdi

import (
	"context"

	clusterv1alpha1 "github.com/karmada-io/karmada/pkg/apis/cluster/v1alpha1"
	workv1alpha2 "github.com/karmada-io/karmada/pkg/apis/work/v1alpha2"
	"github.com/karmada-io/karmada/pkg/scheduler/framework"
)

type IntentDriven struct{}

func (i *IntentDriven) Name() string { return "IntentDriven" }

func (i *IntentDriven) Filter(_ context.Context,
	_ *workv1alpha2.ResourceBindingSpec,
	_ *clusterv1alpha1.Cluster,
	ale *ALE) framework.Code {
	return framework.Success
}

func (i *IntentDriven) Score(_ context.Context,
	_ *workv1alpha2.ResourceBindingSpec,
	_ *clusterv1alpha1.Cluster,
	ale *ALE) (int64, error) {

	A := float64(ale.Accuracy.TargetAccuracy.Value) / 100.0
	L := float64(ale.Latency.LatencyBudgetMs) / 1000.0
	E := float64(ale.Energy.PowerBudgetWatt) / 1000.0

	if L > 1.0 {
		L = 1.0
	}
	if E > 1.0 {
		E = 1.0
	}

	score := int64(0)

	if A > 0.6 {
		score += int64(A * 400)
	}

	if L > 0.7 {
		score += int64(L * 350)
	}

	if E > 0.7 {
		score += int64(E * 300)
	}

	balanced := (A + L + E) / 3.0
	if A <= 0.6 && L <= 0.7 && E <= 0.7 {
		score += int64(balanced * 200)
	}

	if score == 0 {
		score = 500
	}

	if score > 1000 {
		score = 1000
	}

	return score, nil
}
