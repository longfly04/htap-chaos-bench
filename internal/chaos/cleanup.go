package chaos

import "strings"

type CleanupPolicy struct {
	Name              string   `json:"name"`
	Steps             []string `json:"steps"`
	RequiredArtifacts []string `json:"required_artifacts"`
	UnstableWindowMs  int      `json:"unstable_window_ms"`
}

func ResolveCleanupPolicy(name string) CleanupPolicy {
	switch strings.TrimSpace(name) {
	case "pg-restart":
		return CleanupPolicy{
			Name:              "pg-restart",
			Steps:             []string{"terminate chaos sessions", "restart postgres if needed", "re-check observability"},
			RequiredArtifacts: []string{"derived/cleanup-policy.json", "derived/cleanup-report.json", "validation/recovery-check.json"},
			UnstableWindowMs:  5000,
		}
	case "pg-default", "":
		fallthrough
	default:
		return CleanupPolicy{
			Name:              "pg-default",
			Steps:             []string{"wait for worker completion", "close injected sessions", "collect cleanup report"},
			RequiredArtifacts: []string{"derived/cleanup-policy.json", "derived/cleanup-report.json"},
			UnstableWindowMs:  1000,
		}
	}
}
