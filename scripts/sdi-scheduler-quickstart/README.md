# SDI Scheduler Quickstart

A hands-on guide for deploying and testing the SDI Scheduler on top of Karmada.

---

## Overview

The SDI Scheduler replaces the default `karmada-scheduler` with a multi-objective scheduler that routes workloads based on QoS requirements (latency, accuracy, energy). Algorithm selection is done **per-workload via IaC** (PropagationPolicy) — no code changes needed.

```
                    ┌─────────────────────────────────────┐
                    │          Karmada Control Plane       │
                    │                                      │
  kubectl apply  ──►│  PropagationPolicy  ──►  SDI        │──► cluster-A
  (affinityName)    │                      Scheduler      │──► cluster-B
                    │                      (Algorithm)    │──► cluster-C
                    └─────────────────────────────────────┘
```

### Three Algorithms

| Algorithm | affinityName | Best For | Score Formula |
|---|---|---|---|
| **Intent-Driven** | `intent-driven` | Autonomous vehicles, AI inference | `(wL×latency + wA×accuracy + wE×energy) / W × 1000` |
| **Collaborative Swarm** | `collaborative-swarm` | IoT web services, distributed load | `wLoad×fit + wAffinity×fit + 0.2×energy + 0.1×√cap` |
| **Predictive Context** | `predictive-context` | TurtleBot, drones, battery devices | `(0.2×cur + 0.35×pred + 0.2×power + 0.15×stab + 0.1×bat) × confidence` |

---

## Quick Start (5 minutes)

```bash
# Step 1: Check environment
./01-check-status.sh

# Step 2: Deploy SDI Scheduler
./02-deploy-sdi-scheduler.sh

# Step 3: Deploy a test workload (interactive menu)
./04-deploy-workload.sh

# Step 4: Clean up
./05-cleanup.sh
```

---

## Scripts

| Script | Purpose |
|---|---|
| `01-check-status.sh` | Check Karmada connectivity, cluster labels, current scheduler status |
| `02-deploy-sdi-scheduler.sh` | Scale down `karmada-scheduler`, deploy SDI Scheduler + RBAC + ConfigMap |
| `03-switch-algorithm.sh` | Change the **default** algorithm (for workloads with no explicit algorithm) |
| `04-deploy-workload.sh` | Deploy a test workload with a specific algorithm |
| `05-cleanup.sh` | Remove test workloads (optionally remove scheduler and restore karmada-scheduler) |

---

## How Algorithm Selection Works

### Per-Workload (Recommended)

Set `affinityName` in `PropagationPolicy.spec.placement.clusterAffinities[].affinityName`:

```yaml
# manifests/01-workload-intent-driven.yaml
spec:
  placement:
    clusterAffinities:
      - affinityName: intent-driven       # ← Algorithm name here
        labelSelector:
          matchLabels:
            sdi.keti.dev/latency-budget-ms: "50"
            sdi.keti.dev/accuracy-target:   "95"
```

This overrides the default algorithm for that specific workload only.

### Global Default

Change the default for all workloads that don't have an explicit `affinityName`:

```bash
./03-switch-algorithm.sh intent-driven
./03-switch-algorithm.sh collaborative-swarm
./03-switch-algorithm.sh predictive-context
```

This patches `sdi-scheduler-env` ConfigMap and restarts the scheduler.

---

## Algorithm Parameters Reference

### Intent-Driven

Passed via `labelSelector.matchLabels` in PropagationPolicy:

| Label Key | Type | Range | Description |
|---|---|---|---|
| `sdi.keti.dev/latency-budget-ms` | int | 1–10000 | Max acceptable latency (ms) |
| `sdi.keti.dev/accuracy-target` | int | 0–100 | Minimum accuracy (%) |
| `sdi.keti.dev/energy-class` | string | `low`/`medium`/`high` | Energy constraint class |
| `sdi.keti.dev/compute-intensity` | string | `light`/`heavy` | Whether GPU is required |

**Example: Autonomous vehicle workload**
```yaml
affinityName: intent-driven
labelSelector:
  matchLabels:
    sdi.keti.dev/latency-budget-ms: "50"
    sdi.keti.dev/accuracy-target:   "95"
    sdi.keti.dev/energy-class:      "medium"
    sdi.keti.dev/compute-intensity: "heavy"
```

---

### Collaborative Swarm

| Label Key | Type | Range | Description |
|---|---|---|---|
| `sdi.keti.dev/region` | string | e.g. `kr-south` | Geographic region preference |
| `sdi.keti.dev/energy-class` | string | `low`/`medium`/`high` | Energy preference |
| `sdi.keti.dev/load-balance-weight` | float | 0.0–1.0 | Weight for load balancing score |
| `sdi.keti.dev/affinity-weight` | float | 0.0–1.0 | Weight for region affinity score |

**Example: Distributed IoT service**
```yaml
affinityName: collaborative-swarm
labelSelector:
  matchLabels:
    sdi.keti.dev/region:               "kr-south"
    sdi.keti.dev/energy-class:         "low"
    sdi.keti.dev/load-balance-weight:  "0.6"
    sdi.keti.dev/affinity-weight:      "0.4"
```

---

### Predictive Context

| Label Key | Type | Range | Description |
|---|---|---|---|
| `sdi.keti.dev/power-budget-watt` | int | 0+ (0=no limit) | Max power consumption (W) |
| `sdi.keti.dev/cpu-threshold` | float | 0.0–2.0 | Max CPU utilization (1.0=100%, 2.0=200% overcommit) |
| `sdi.keti.dev/mem-threshold` | float | 0.0–2.0 | Max memory utilization |
| `sdi.keti.dev/battery-threshold` | float | 0.0–1.0 | Minimum battery level (mobile only) |
| `sdi.keti.dev/time-horizon-sec` | int | 1+ | Prediction horizon (seconds) |

**Example: TurtleBot / drone workload**
```yaml
affinityName: predictive-context
labelSelector:
  matchLabels:
    sdi.keti.dev/power-budget-watt: "30"
    sdi.keti.dev/cpu-threshold:     "0.8"
    sdi.keti.dev/battery-threshold: "0.3"
    sdi.keti.dev/time-horizon-sec:  "300"
```

**Inject prediction data via cluster labels:**
```bash
kubectl --kubeconfig=/etc/karmada/karmada-apiserver.config \
  label cluster edge-cluster \
    sdi.keti.dev/cluster-type=edge \
    sdi.keti.dev/cpu-usage=0.65 \
    sdi.keti.dev/mem-usage=0.50 \
    sdi.keti.dev/power-watt=25 \
    sdi.keti.dev/pred-cpu-usage=0.70 \
    sdi.keti.dev/pred-mem-usage=0.55 \
    sdi.keti.dev/cpu-trend=stable \
    sdi.keti.dev/pred-confidence=0.85
```

---

## Configuring the Scheduler (ConfigMap)

All runtime parameters live in `sdi-scheduler-env` ConfigMap:

```bash
kubectl --kubeconfig=/etc/karmada/karmada-apiserver.config \
  edit configmap sdi-scheduler-env -n karmada-system
```

```yaml
data:
  SDI_DEFAULT_ALGORITHM: "intent-driven"   # default algorithm

  # ALE global defaults (used when Analysis Engine is unavailable)
  MALE_ACCURACY: "90"      # accuracy target (0-100)
  MALE_LATENCY:  "100"     # latency budget (ms)
  MALE_ENERGY:   "100"     # energy budget (watt)

  # Analysis Engine address (optional)
  # ANALYSIS_ENGINE_ADDR: "http://analysis-engine.sdi-system.svc.cluster.local:5000"

  SDI_DEBUG: "true"        # verbose logging
```

After editing, restart the scheduler to apply changes:
```bash
kubectl --kubeconfig=/etc/karmada/karmada-apiserver.config \
  rollout restart deployment/sdi-scheduler -n karmada-system
```

---

## Verifying Scheduling Results

```bash
KKC="kubectl --kubeconfig=/etc/karmada/karmada-apiserver.config"

# 1. Check which clusters were selected
${KKC} get resourcebinding -n sdi-test -o wide

# 2. See score details in logs
${KKC} logs -n karmada-system -l app=sdi-scheduler --tail=50 | grep -E "(score|selected|algorithm)"

# 3. Check all cluster labels used as scheduler inputs
${KKC} get clusters --show-labels
```

---

## Troubleshooting

### Scheduler not running
```bash
KKC="kubectl --kubeconfig=/etc/karmada/karmada-apiserver.config"
${KKC} get pods -n karmada-system -l app=sdi-scheduler
${KKC} logs -n karmada-system -l app=sdi-scheduler --tail=30
```

### Leader Election conflict (two schedulers competing)
```bash
# Scale down karmada-scheduler first
${KKC} scale deployment karmada-scheduler -n karmada-system --replicas=0

# Delete the old SDI scheduler pod to release the Lease
${KKC} delete pods -n karmada-system -l app=sdi-scheduler
```

### ResourceBinding stuck (not scheduled)
```bash
# Check if sdi-scheduler is set as schedulerName in PropagationPolicy
${KKC} get propagationpolicy -n sdi-test -o yaml | grep schedulerName

# Check ResourceBinding events
${KKC} describe resourcebinding -n sdi-test <binding-name>
```

### No clusters match the filter
The algorithm's filter criteria may be too strict. Check cluster labels:
```bash
# Add required labels manually for testing
${KKC} label cluster <cluster-name> sdi.keti.dev/cluster-type=edge

# Or relax constraints in the PropagationPolicy labelSelector
```

---

## Architecture

```
 PropagationPolicy (IaC)
   affinityName: "intent-driven"    ← Algorithm selection
   labelSelector:                   ← Algorithm parameters
     sdi.keti.dev/latency-budget-ms: "50"
          │
          ▼
 SDI Scheduler (karmada-system)
   normalizeAlgorithm(affinityName) → IntentDriven / CollaborativeSwarm / PredictiveContext
          │
          ▼
 Filter Phase                        Score Phase
   hasMinimumResources()               calculateLatencyScore()
   meetsLatencyRequirement()           calculateAccuracyScore()
   powerBudgetCheck()                  calculateEnergyScore()
          │                                    │
          └─────────────── Best Cluster ───────┘
                                │
                                ▼
                       ResourceBinding.spec.clusters
                       [{ name: "edge-cluster", replicas: 1 }]
```

---

## File Structure

```
scripts/sdi-scheduler-quickstart/
├── README.md                          # This file
├── 01-check-status.sh                 # Pre-flight check
├── 02-deploy-sdi-scheduler.sh         # Deploy SDI Scheduler
├── 03-switch-algorithm.sh             # Switch default algorithm
├── 04-deploy-workload.sh              # Deploy test workload
├── 05-cleanup.sh                      # Clean up resources
└── manifests/
    ├── 01-workload-intent-driven.yaml  # Intent-Driven example
    ├── 02-workload-swarm.yaml          # Collaborative Swarm example
    └── 03-workload-predictive.yaml     # Predictive Context example
```

---

## Related Paths

| Component | Path |
|---|---|
| SDI Scheduler source | `deploy/release_2/src/karmada/pkg/scheduler/framework/plugins/sdi/` |
| MALE Operator source | `deploy/SDI/male-operator/` |
| Analysis Engine source | `deploy/release_2/src/analysis-engine/` |
| Metric Collector source | `deploy/release_2/src/metric-collector/` |
| Deploy manifests (release_2) | `deploy/male-operator-0123/` |
