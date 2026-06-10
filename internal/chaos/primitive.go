package chaos

import (
	"fmt"
	"strings"
)

type PrimitivePolicy struct {
	Primitive       string      `json:"primitive"`
	Family          string      `json:"family"`
	SafetyLevel     SafetyLevel  `json:"safety_level"`
	CleanupProfile  string      `json:"cleanup_profile"`
	SelectorKind    string      `json:"selector_kind"`
	RequiresFixture  bool        `json:"requires_fixture"`
	RequiredTarget  string      `json:"required_target,omitempty"`
}

var primitivePolicies = map[string]PrimitivePolicy{
	"wait_xact": {
		Primitive:      "wait_xact",
		Family:         "lock-path",
		SafetyLevel:    SafetyLevelMainline,
		CleanupProfile: "pg-default",
		SelectorKind:   "tp-hotspot",
		RequiresFixture: true,
	},
	"deadlock_pair": {
		Primitive:      "deadlock_pair",
		Family:         "lock-path",
		SafetyLevel:    SafetyLevelMainline,
		CleanupProfile: "pg-default",
		SelectorKind:   "fixture_rows",
		RequiresFixture: true,
		RequiredTarget:  "fixture_rows:2",
	},
	"spill_pressure": {
		Primitive:      "spill_pressure",
		Family:         "memory-path",
		SafetyLevel:    SafetyLevelMainline,
		CleanupProfile: "pg-default",
		SelectorKind:   "ap_query_class",
		RequiresFixture: false,
	},
	"idle_xact": {
		Primitive:      "idle_xact",
		Family:         "session-path",
		SafetyLevel:    SafetyLevelDiagnostic,
		CleanupProfile: "pg-default",
		SelectorKind:   "session",
	},
	"fork_burst": {
		Primitive:      "fork_burst",
		Family:         "process-path",
		SafetyLevel:    SafetyLevelDiagnostic,
		CleanupProfile: "pg-default",
		SelectorKind:   "process",
	},
	"conn_exhaust": {
		Primitive:      "conn_exhaust",
		Family:         "session-path",
		SafetyLevel:    SafetyLevelSandboxOnly,
		CleanupProfile: "pg-restart",
		SelectorKind:   "session",
	},
	"terminate": {
		Primitive:      "terminate",
		Family:         "session-path",
		SafetyLevel:    SafetyLevelSandboxOnly,
		CleanupProfile: "pg-restart",
		SelectorKind:   "session",
	},
}

func ResolvePrimitivePolicy(primitive string, safetyLevel string, cleanupProfile string) (PrimitivePolicy, error) {
	base, ok := primitivePolicies[strings.TrimSpace(primitive)]
	if !ok {
		return PrimitivePolicy{}, fmt.Errorf("unsupported chaos primitive: %s", primitive)
	}
	if override := strings.TrimSpace(cleanupProfile); override != "" {
		base.CleanupProfile = override
	}
	if override := NormalizeSafetyLevel(safetyLevel); strings.TrimSpace(safetyLevel) != "" {
		base.SafetyLevel = override
	}
	return base, nil
}

func SupportedPrimitives() []string {
	primitives := make([]string, 0, len(primitivePolicies))
	for primitive := range primitivePolicies {
		primitives = append(primitives, primitive)
	}
	return primitives
}
