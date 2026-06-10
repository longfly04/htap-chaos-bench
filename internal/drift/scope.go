package drift

import (
	"fmt"
	"strings"
)

var defaultWorkloadFeatureScope = []string{
	"query_class",
	"table_count",
	"join_count",
	"predicate_count",
	"tables",
	"predicates",
}

var supportedFeatureScopes = map[string]struct{}{
	"query_class":        {},
	"table_count":        {},
	"join_count":         {},
	"predicate_count":    {},
	"tables":             {},
	"predicates":         {},
	"aliasname_fullname": {},
}

func DefaultFeatureScope() []string {
	return append([]string(nil), defaultWorkloadFeatureScope...)
}

func ParseFeatureScope(raw string) []string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil
	}
	parts := strings.FieldsFunc(raw, func(r rune) bool {
		return r == ',' || r == ';' || r == '|' || r == ' ' || r == '\t' || r == '\n' || r == '\r'
	})
	return NormalizeFeatureScope(parts)
}

func NormalizeFeatureScope(scope []string) []string {
	cleaned := make([]string, 0, len(scope))
	seen := map[string]struct{}{}
	for _, feature := range scope {
		feature = strings.TrimSpace(feature)
		if feature == "" {
			continue
		}
		if _, ok := supportedFeatureScopes[feature]; !ok {
			continue
		}
		if _, ok := seen[feature]; ok {
			continue
		}
		seen[feature] = struct{}{}
		cleaned = append(cleaned, feature)
	}
	if len(cleaned) == 0 {
		return DefaultFeatureScope()
	}
	return cleaned
}

func ValidateFeatureScope(scope []string) error {
	for _, feature := range scope {
		feature = strings.TrimSpace(feature)
		if feature == "" {
			continue
		}
		if _, ok := supportedFeatureScopes[feature]; !ok {
			return fmt.Errorf("scenario.drift.feature_scope is invalid: %s", feature)
		}
	}
	return nil
}
