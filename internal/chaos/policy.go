package chaos

import (
	"fmt"
	"strings"
)

type SafetyLevel string

const (
	SafetyLevelMainline    SafetyLevel = "mainline"
	SafetyLevelDiagnostic  SafetyLevel = "diagnostic"
	SafetyLevelSandboxOnly SafetyLevel = "sandbox-only"
)

func NormalizeSafetyLevel(value string) SafetyLevel {
	switch strings.TrimSpace(strings.ToLower(value)) {
	case string(SafetyLevelDiagnostic):
		return SafetyLevelDiagnostic
	case string(SafetyLevelSandboxOnly):
		return SafetyLevelSandboxOnly
	case string(SafetyLevelMainline):
		return SafetyLevelMainline
	default:
		return SafetyLevelMainline
	}
}

func ValidateSafetyLevel(value string) error {
	value = strings.TrimSpace(strings.ToLower(value))
	switch value {
	case "", string(SafetyLevelMainline), string(SafetyLevelDiagnostic), string(SafetyLevelSandboxOnly):
		return nil
	default:
		return fmt.Errorf("invalid chaos safety level: %s", value)
	}
}
