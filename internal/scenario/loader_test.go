package scenario

import "testing"

func TestValidateDeadlockPairScenario(t *testing.T) {
	s := Scenario{
		System:   "pg-like",
		Dataset:  "job",
		Snapshot: "snap-1",
		Budget:   "moderate",
		TP: TPConfig{
			Profile:     "generated",
			Concurrency: 4,
			Terminals:   4,
			RateCap:     0,
			Intensity:   TPIntensity{BatchSize: 128},
			Skew:        TPSkew{Mode: "hotspot", HotModulus: 64, HotRemainder: 1},
			Burst:       TPBurst{Mode: "steady"},
		},
		AP: APConfig{
			Class:                "sort-heavy",
			Arrival:              "tp-first",
			Terminals:            1,
			BurstIntervalSeconds: 5,
		},
		Chaos: ChaosConfig{
			Mode:              "single-fault",
			Stage:             "mixed-steady-state",
			StartAfterSeconds: 10,
			DurationSeconds:   15,
			Seed:              1,
			Injections: []ChaosInjection{{
				ID:             "cross_update_deadlock",
				Family:         "lock-path",
				Primitive:      "deadlock_pair",
				TargetSelector: "fixture_rows:2",
				Intensity:      "L1",
				Params: ChaosParams{
					Jobs: 1,
				},
			}},
		},
		Drift: DriftConfig{DataFactor: 0, WorkloadFactor: 0},
		Seed:  1,
	}

	if err := s.Validate(); err != nil {
		t.Fatalf("Validate() error = %v, want nil", err)
	}
}

func TestValidateDeadlockPairRequiresFixtureRowsSelector(t *testing.T) {
	s := Scenario{
		System:   "pg-like",
		Dataset:  "job",
		Snapshot: "snap-1",
		Budget:   "moderate",
		TP: TPConfig{
			Profile:     "generated",
			Concurrency: 4,
			Terminals:   4,
			RateCap:     0,
			Intensity:   TPIntensity{BatchSize: 128},
			Skew:        TPSkew{Mode: "hotspot", HotModulus: 64, HotRemainder: 1},
			Burst:       TPBurst{Mode: "steady"},
		},
		AP: APConfig{
			Class:                "sort-heavy",
			Arrival:              "tp-first",
			Terminals:            1,
			BurstIntervalSeconds: 5,
		},
		Chaos: ChaosConfig{
			Mode:              "single-fault",
			Stage:             "mixed-steady-state",
			StartAfterSeconds: 10,
			DurationSeconds:   15,
			Seed:              1,
			Injections: []ChaosInjection{{
				ID:             "cross_update_deadlock",
				Family:         "lock-path",
				Primitive:      "deadlock_pair",
				TargetSelector: "tp-hotspot/movie_freshness",
				Intensity:      "L1",
				Params: ChaosParams{
					Jobs: 1,
				},
			}},
		},
		Drift: DriftConfig{DataFactor: 0, WorkloadFactor: 0},
		Seed:  1,
	}

	if err := s.Validate(); err == nil {
		t.Fatalf("Validate() error = nil, want deadlock_pair fixture_rows validation error")
	}
}

func TestValidateQueryOrientedHTAPCheckScenario(t *testing.T) {
	s := Scenario{
		System:   "pg-like",
		Dataset:  "job",
		Snapshot: "snap-1",
		Budget:   "moderate",
		TP: TPConfig{
			Profile:     "generated",
			Concurrency: 4,
			Terminals:   4,
			RateCap:     0,
			Intensity:   TPIntensity{BatchSize: 128},
			Skew:        TPSkew{Mode: "hotspot", HotModulus: 64, HotRemainder: 1},
			Burst:       TPBurst{Mode: "steady"},
		},
		AP: APConfig{
			Class:                "sort-heavy",
			Arrival:              "tp-first",
			Terminals:            1,
			BurstIntervalSeconds: 5,
		},
		HTAPCheck: HTAPCheckConfig{
			Enabled: true,
			Type:    "query-oriented",
		},
		Chaos: ChaosConfig{Mode: "none"},
		Drift: DriftConfig{DataFactor: 0, WorkloadFactor: 0},
		Seed:  1,
	}

	if err := s.Validate(); err != nil {
		t.Fatalf("Validate() error = %v, want nil", err)
	}
}

func TestValidateSyncLatencyHTAPCheckScenario(t *testing.T) {
	s := Scenario{
		System:   "pg-like",
		Dataset:  "job",
		Snapshot: "snap-1",
		Budget:   "moderate",
		TP: TPConfig{
			Profile:     "generated",
			Concurrency: 4,
			Terminals:   4,
			RateCap:     0,
			Intensity:   TPIntensity{BatchSize: 128},
			Skew:        TPSkew{Mode: "hotspot", HotModulus: 64, HotRemainder: 1},
			Burst:       TPBurst{Mode: "steady"},
		},
		AP: APConfig{
			Class:                "sort-heavy",
			Arrival:              "tp-first",
			Terminals:            1,
			BurstIntervalSeconds: 5,
		},
		HTAPCheck: HTAPCheckConfig{
			Enabled: true,
			Type:    "sync-latency",
		},
		Chaos: ChaosConfig{Mode: "none"},
		Drift: DriftConfig{DataFactor: 0, WorkloadFactor: 0},
		Seed:  1,
	}

	if err := s.Validate(); err != nil {
		t.Fatalf("Validate() error = %v, want nil", err)
	}
}

func TestValidateWorkloadDriftScenario(t *testing.T) {
	s := Scenario{
		System:   "pg-like",
		Dataset:  "job",
		Snapshot: "snap-1",
		Budget:   "moderate",
		TP: TPConfig{
			Profile:     "generated",
			Concurrency: 4,
			Terminals:   4,
			RateCap:     0,
			Intensity:   TPIntensity{BatchSize: 128},
			Skew:        TPSkew{Mode: "hotspot", HotModulus: 64, HotRemainder: 1},
			Burst:       TPBurst{Mode: "steady"},
		},
		AP: APConfig{
			Class:                "sort-heavy",
			Arrival:              "tp-first",
			Terminals:            1,
			BurstIntervalSeconds: 5,
		},
		Chaos: ChaosConfig{Mode: "none"},
		Drift: DriftConfig{DataFactor: 0, WorkloadFactor: 0.6},
		Seed:  1,
	}

	if err := s.Validate(); err != nil {
		t.Fatalf("Validate() error = %v, want nil", err)
	}
}

func TestValidateWorkloadDriftRejectsOutOfRangeFactor(t *testing.T) {
	s := Scenario{
		System:   "pg-like",
		Dataset:  "job",
		Snapshot: "snap-1",
		Budget:   "moderate",
		TP: TPConfig{
			Profile:     "generated",
			Concurrency: 4,
			Terminals:   4,
			RateCap:     0,
			Intensity:   TPIntensity{BatchSize: 128},
			Skew:        TPSkew{Mode: "hotspot", HotModulus: 64, HotRemainder: 1},
			Burst:       TPBurst{Mode: "steady"},
		},
		AP: APConfig{
			Class:                "sort-heavy",
			Arrival:              "tp-first",
			Terminals:            1,
			BurstIntervalSeconds: 5,
		},
		Chaos: ChaosConfig{Mode: "none"},
		Drift: DriftConfig{DataFactor: 0, WorkloadFactor: 1.2},
		Seed:  1,
	}

	if err := s.Validate(); err == nil {
		t.Fatalf("Validate() error = nil, want drift.workload_factor range error")
	}
}

func TestValidateWorkloadDriftRequiresAPClass(t *testing.T) {
	s := Scenario{
		System:   "pg-like",
		Dataset:  "job",
		Snapshot: "snap-1",
		Budget:   "moderate",
		TP: TPConfig{
			Profile:     "generated",
			Concurrency: 4,
			Terminals:   4,
			RateCap:     0,
			Intensity:   TPIntensity{BatchSize: 128},
			Skew:        TPSkew{Mode: "hotspot", HotModulus: 64, HotRemainder: 1},
			Burst:       TPBurst{Mode: "steady"},
		},
		AP: APConfig{
			Arrival:              "tp-first",
			Terminals:            1,
			BurstIntervalSeconds: 5,
		},
		Chaos: ChaosConfig{Mode: "none"},
		Drift: DriftConfig{DataFactor: 0, WorkloadFactor: 0.5},
		Seed:  1,
	}

	if err := s.Validate(); err == nil {
		t.Fatalf("Validate() error = nil, want workload drift AP class validation error")
	}
}

func TestValidateHTAPCheckRejectsUnknownType(t *testing.T) {
	s := Scenario{
		System:   "pg-like",
		Dataset:  "job",
		Snapshot: "snap-1",
		Budget:   "moderate",
		TP: TPConfig{
			Profile:     "generated",
			Concurrency: 4,
			Terminals:   4,
			RateCap:     0,
			Intensity:   TPIntensity{BatchSize: 128},
			Skew:        TPSkew{Mode: "hotspot", HotModulus: 64, HotRemainder: 1},
			Burst:       TPBurst{Mode: "steady"},
		},
		AP: APConfig{
			Class:                "sort-heavy",
			Arrival:              "tp-first",
			Terminals:            1,
			BurstIntervalSeconds: 5,
		},
		HTAPCheck: HTAPCheckConfig{
			Enabled: true,
			Type:    "unknown-mode",
		},
		Chaos: ChaosConfig{Mode: "none"},
		Drift: DriftConfig{DataFactor: 0, WorkloadFactor: 0},
		Seed:  1,
	}

	if err := s.Validate(); err == nil {
		t.Fatalf("Validate() error = nil, want htap_check type validation error")
	}
}

func TestValidateSpillPressureScenario(t *testing.T) {
	s := Scenario{
		System:   "pg-like",
		Dataset:  "job",
		Snapshot: "snap-1",
		Budget:   "moderate",
		TP: TPConfig{
			Profile:     "generated",
			Concurrency: 4,
			Terminals:   4,
			RateCap:     0,
			Intensity:   TPIntensity{BatchSize: 128},
			Skew:        TPSkew{Mode: "hotspot", HotModulus: 64, HotRemainder: 1},
			Burst:       TPBurst{Mode: "steady"},
		},
		AP: APConfig{
			Class:                "sort-heavy",
			Arrival:              "tp-first",
			Terminals:            1,
			BurstIntervalSeconds: 5,
		},
		Chaos: ChaosConfig{
			Mode:              "single-fault",
			Stage:             "mixed-steady-state",
			StartAfterSeconds: 10,
			DurationSeconds:   15,
			Seed:              1,
			Injections: []ChaosInjection{{
				ID:             "spill_sort_l1",
				Family:         "memory-path",
				Primitive:      "spill_pressure",
				TargetSelector: "ap_query_class:sort-heavy",
				Intensity:      "L1",
				Params: ChaosParams{
					Workers:       1,
					SessionMemory: "64kB",
					Rate:          1.0,
				},
			}},
		},
		Drift: DriftConfig{DataFactor: 0, WorkloadFactor: 0},
		Seed:  1,
	}

	if err := s.Validate(); err != nil {
		t.Fatalf("Validate() error = %v, want nil", err)
	}
}

func TestValidateSpillPressureRequiresSessionMemory(t *testing.T) {
	s := Scenario{
		System:   "pg-like",
		Dataset:  "job",
		Snapshot: "snap-1",
		Budget:   "moderate",
		TP: TPConfig{
			Profile:     "generated",
			Concurrency: 4,
			Terminals:   4,
			RateCap:     0,
			Intensity:   TPIntensity{BatchSize: 128},
			Skew:        TPSkew{Mode: "hotspot", HotModulus: 64, HotRemainder: 1},
			Burst:       TPBurst{Mode: "steady"},
		},
		AP: APConfig{
			Class:                "sort-heavy",
			Arrival:              "tp-first",
			Terminals:            1,
			BurstIntervalSeconds: 5,
		},
		Chaos: ChaosConfig{
			Mode:              "single-fault",
			Stage:             "mixed-steady-state",
			StartAfterSeconds: 10,
			DurationSeconds:   15,
			Seed:              1,
			Injections: []ChaosInjection{{
				ID:             "spill_sort_l1",
				Family:         "memory-path",
				Primitive:      "spill_pressure",
				TargetSelector: "ap_query_class:sort-heavy",
				Intensity:      "L1",
				Params: ChaosParams{
					Workers: 1,
					Rate:    1.0,
				},
			}},
		},
		Drift: DriftConfig{DataFactor: 0, WorkloadFactor: 0},
		Seed:  1,
	}

	if err := s.Validate(); err == nil {
		t.Fatalf("Validate() error = nil, want spill_pressure session_memory validation error")
	}
}
