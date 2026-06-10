package scenario

import (
	"fmt"
	"os"
	"strings"

	"gopkg.in/yaml.v3"
)

var allowedChaosSafetyLevels = map[string]struct{}{
	"mainline":      {},
	"diagnostic":    {},
	"sandbox-only": {},
}

var allowedDriftFeatureScopes = map[string]struct{}{
	"query_class":        {},
	"table_count":        {},
	"join_count":         {},
	"predicate_count":    {},
	"tables":             {},
	"predicates":         {},
	"aliasname_fullname": {},
}

func LoadScenario(path string) (Scenario, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return Scenario{}, err
	}
	var scenario Scenario
	if err := yaml.Unmarshal(data, &scenario); err != nil {
		return Scenario{}, err
	}
	if err := scenario.Validate(); err != nil {
		return Scenario{}, err
	}
	return scenario, nil
}

func (s Scenario) Validate() error {
	if s.System == "" {
		return fmt.Errorf("scenario.system is required")
	}
	if s.Dataset == "" {
		return fmt.Errorf("scenario.dataset is required")
	}
	if s.TP.Profile == "" {
		return fmt.Errorf("scenario.tp.profile is required")
	}
	if s.TP.Concurrency <= 0 {
		return fmt.Errorf("scenario.tp.concurrency must be > 0")
	}
	if s.TP.Terminals < 0 {
		return fmt.Errorf("scenario.tp.terminals must be >= 0")
	}
	if s.TP.RateCap < 0 {
		return fmt.Errorf("scenario.tp.rate_cap must be >= 0")
	}
	if s.TP.Intensity.BatchSize <= 0 {
		return fmt.Errorf("scenario.tp.intensity.batch_size must be > 0")
	}
	if s.TP.Skew.HotModulus <= 0 {
		return fmt.Errorf("scenario.tp.skew.hot_modulus must be > 0")
	}
	if s.TP.Skew.HotRemainder < 0 {
		return fmt.Errorf("scenario.tp.skew.hot_remainder must be >= 0")
	}
	if s.AP.Terminals < 0 {
		return fmt.Errorf("scenario.ap.terminals must be >= 0")
	}
	if s.AP.Parallelism < 0 {
		return fmt.Errorf("scenario.ap.parallelism must be >= 0")
	}
	if s.AP.BurstIntervalSeconds < 0 {
		return fmt.Errorf("scenario.ap.burst_interval_seconds must be >= 0")
	}
	if s.AP.Arrival != "" {
		switch s.AP.Arrival {
		case "tp-first", "ap-first", "repeated-burst", "freshness-overlap":
		default:
			return fmt.Errorf("scenario.ap.arrival is invalid: %s", s.AP.Arrival)
		}
	}
	if s.HTAPCheck.Enabled && strings.TrimSpace(s.HTAPCheck.Type) == "" {
		return fmt.Errorf("scenario.htap_check.type is required when htap_check.enabled is true")
	}
	if s.HTAPCheck.Type != "" {
		switch strings.TrimSpace(s.HTAPCheck.Type) {
		case "query-oriented", "sync-latency":
		default:
			return fmt.Errorf("scenario.htap_check.type is invalid: %s", s.HTAPCheck.Type)
		}
	}
	if s.Drift.DataFactor < 0 || s.Drift.DataFactor > 1 {
		return fmt.Errorf("scenario.drift.data_factor must be within [0,1]")
	}
	if s.Drift.WorkloadFactor < 0 || s.Drift.WorkloadFactor > 1 {
		return fmt.Errorf("scenario.drift.workload_factor must be within [0,1]")
	}
	if err := validateFeatureScope(s.Drift.FeatureScope); err != nil {
		return err
	}
	if s.Drift.WorkloadFactor > 0 && strings.TrimSpace(s.AP.Class) == "" {
		return fmt.Errorf("scenario.ap.class is required when drift.workload_factor > 0")
	}
	if safetyLevel := strings.TrimSpace(s.Chaos.SafetyLevel); safetyLevel != "" {
		if _, ok := allowedChaosSafetyLevels[safetyLevel]; !ok {
			return fmt.Errorf("scenario.chaos.safety_level is invalid: %s", s.Chaos.SafetyLevel)
		}
	}

	switch s.Chaos.Mode {
	case "", "none":
		if len(s.Chaos.Injections) > 0 {
			return fmt.Errorf("scenario.chaos.injections must be empty when chaos mode is none")
		}
	case "single-fault", "multi-fault", "randomized-fault":
	default:
		return fmt.Errorf("scenario.chaos.mode is invalid: %s", s.Chaos.Mode)
	}
	if s.Chaos.Stage != "" {
		switch s.Chaos.Stage {
		case "tp-only", "ap-only", "mixed-steady-state", "recovery-window":
		default:
			return fmt.Errorf("scenario.chaos.stage is invalid: %s", s.Chaos.Stage)
		}
	}
	if s.Chaos.StartAfterSeconds < 0 {
		return fmt.Errorf("scenario.chaos.start_after_seconds must be >= 0")
	}
	if s.Chaos.DurationSeconds < 0 {
		return fmt.Errorf("scenario.chaos.duration_seconds must be >= 0")
	}
	if s.Chaos.Mode == "single-fault" && len(s.Chaos.Injections) != 1 {
		return fmt.Errorf("scenario.chaos.single-fault requires exactly one injection")
	}
	for _, injection := range s.Chaos.Injections {
		if injection.ID == "" {
			return fmt.Errorf("scenario.chaos.injection.id is required")
		}
		if injection.Family == "" {
			return fmt.Errorf("scenario.chaos.injection.family is required")
		}
		if injection.Primitive == "" {
			return fmt.Errorf("scenario.chaos.injection.primitive is required")
		}
		if injection.TargetSelector == "" {
			return fmt.Errorf("scenario.chaos.injection.target_selector is required")
		}
		if injection.Intensity == "" {
			return fmt.Errorf("scenario.chaos.injection.intensity is required")
		}
		if injection.Params.Jobs < 0 {
			return fmt.Errorf("scenario.chaos.injection.params.jobs must be >= 0")
		}
		if injection.Params.LockHoldSeconds < 0 {
			return fmt.Errorf("scenario.chaos.injection.params.lock_hold_seconds must be >= 0")
		}
		if injection.Params.Workers < 0 {
			return fmt.Errorf("scenario.chaos.injection.params.workers must be >= 0")
		}
		if injection.Params.Rate < 0 {
			return fmt.Errorf("scenario.chaos.injection.params.rate must be >= 0")
		}
		switch injection.Primitive {
		case "wait_xact":
			if injection.Params.Jobs <= 0 {
				return fmt.Errorf("scenario.chaos.wait_xact.params.jobs must be > 0")
			}
			if injection.Params.LockHoldSeconds <= 0 {
				return fmt.Errorf("scenario.chaos.wait_xact.params.lock_hold_seconds must be > 0")
			}
		case "deadlock_pair":
			if injection.Params.Jobs != 1 {
				return fmt.Errorf("scenario.chaos.deadlock_pair.params.jobs must be 1 for the minimal pair implementation")
			}
			if !strings.HasPrefix(strings.TrimSpace(injection.TargetSelector), "fixture_rows:") {
				return fmt.Errorf("scenario.chaos.deadlock_pair.target_selector must use fixture_rows:<n>")
			}
		case "spill_pressure":
			if injection.Params.Workers <= 0 {
				return fmt.Errorf("scenario.chaos.spill_pressure.params.workers must be > 0")
			}
			if strings.TrimSpace(injection.Params.SessionMemory) == "" {
				return fmt.Errorf("scenario.chaos.spill_pressure.params.session_memory is required")
			}
			if injection.Params.Rate <= 0 {
				return fmt.Errorf("scenario.chaos.spill_pressure.params.rate must be > 0")
			}
		}
	}
	return nil
}

func validateFeatureScope(scope []string) error {
	for _, feature := range scope {
		feature = strings.TrimSpace(feature)
		if feature == "" {
			continue
		}
		if _, ok := allowedDriftFeatureScopes[feature]; !ok {
			return fmt.Errorf("scenario.drift.feature_scope is invalid: %s", feature)
		}
	}
	return nil
}
