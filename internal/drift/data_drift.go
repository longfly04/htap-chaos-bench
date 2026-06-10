package drift

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"htap-chaos-bench/internal/dataset"
)

type DataDriftProfile struct {
	Enabled                   bool     `json:"enabled"`
	DataFactor                float64  `json:"data_factor"`
	FeatureScope              []string `json:"feature_scope"`
	SupportsDrift             bool     `json:"supports_drift"`
	QueryFeatureBinsSource    string   `json:"query_feature_bins_source,omitempty"`
	DriftApplicableColumnsSrc string   `json:"drift_applicable_columns_source,omitempty"`
	ColumnNamesSource         string   `json:"column_names_source,omitempty"`
	ProfilePath               string   `json:"profile_path"`
	FactorPath                string   `json:"factor_path"`
	PlanPath                  string   `json:"plan_path"`
	Status                    string   `json:"status"`
}

func MaterializeDataDrift(datasetRoot string, pack dataset.Pack, derivedDir string, featureScope []string, dataFactor float64, seed int) (*DataDriftProfile, error) {
	if dataFactor < 0 || dataFactor > 1 {
		return nil, fmt.Errorf("scenario.drift.data_factor must be within [0,1]")
	}
	if dataFactor <= 0 {
		return nil, nil
	}
	if err := os.MkdirAll(derivedDir, 0o755); err != nil {
		return nil, err
	}

	scope := NormalizeFeatureScope(featureScope)
	queryBinsSource := strings.TrimSpace(pack.QueryFeatureBins)
	if queryBinsSource == "" {
		queryBinsSource = "metadata/query_feature_bins.json"
	}
	driftApplicableSource := strings.TrimSpace(pack.DriftApplicableColumns)
	if driftApplicableSource == "" {
		driftApplicableSource = "metadata/drift_applicable_columns.yaml"
	}
	columnNamesSource := strings.TrimSpace(pack.ColumnNames)
	if columnNamesSource == "" {
		columnNamesSource = "metadata/column_names.yaml"
	}

	metadataPaths := []string{
		filepath.ToSlash(filepath.Join(datasetRoot, filepath.FromSlash(queryBinsSource))),
		filepath.ToSlash(filepath.Join(datasetRoot, filepath.FromSlash(driftApplicableSource))),
		filepath.ToSlash(filepath.Join(datasetRoot, filepath.FromSlash(columnNamesSource))),
	}
	metadataComplete := true
	for _, path := range metadataPaths {
		if _, err := os.Stat(path); err != nil {
			metadataComplete = false
			break
		}
	}

	status := "contract-only"
	if pack.SupportsDrift && metadataComplete {
		status = "planned"
	}

	roundCount := 1 + int(dataFactor*2)
	if roundCount <= 0 {
		roundCount = 1
	}
	rounds := make([]map[string]any, 0, roundCount)
	for round := 1; round <= roundCount; round++ {
		rounds = append(rounds, map[string]any{
			"round":               round,
			"seed":                seed + round,
			"data_factor":         roundMetric(dataFactor),
			"feature_scope":       scope,
			"row_update_count":    round * 100,
			"js_divergence_target": roundMetric(float64(round) * dataFactor / float64(roundCount)),
		})
	}

	profile := DataDriftProfile{
		Enabled:                   true,
		DataFactor:                roundMetric(dataFactor),
		FeatureScope:              scope,
		SupportsDrift:             pack.SupportsDrift,
		QueryFeatureBinsSource:    queryBinsSource,
		DriftApplicableColumnsSrc: driftApplicableSource,
		ColumnNamesSource:         columnNamesSource,
		ProfilePath:               "derived/data-drift-profile.json",
		FactorPath:                "derived/data-drift-factor.json",
		PlanPath:                  "derived/drift-plan.json",
		Status:                    status,
	}

	if err := writeJSON(filepath.Join(derivedDir, "data-drift-profile.json"), profile); err != nil {
		return nil, err
	}
	if err := writeJSON(filepath.Join(derivedDir, "data-drift-factor.json"), map[string]any{
		"enabled":                    profile.Enabled,
		"data_factor":                profile.DataFactor,
		"feature_scope":              profile.FeatureScope,
		"supports_drift":             profile.SupportsDrift,
		"query_feature_bins_source":  profile.QueryFeatureBinsSource,
		"drift_applicable_columns_source": profile.DriftApplicableColumnsSrc,
		"column_names_source":        profile.ColumnNamesSource,
		"profile_path":               profile.ProfilePath,
		"plan_path":                  profile.PlanPath,
		"status":                     profile.Status,
	}); err != nil {
		return nil, err
	}
	if err := writeJSON(filepath.Join(derivedDir, "drift-plan.json"), map[string]any{
		"enabled":             true,
		"data_factor":         profile.DataFactor,
		"feature_scope":       profile.FeatureScope,
		"supports_drift":      profile.SupportsDrift,
		"metadata_complete":    metadataComplete,
		"metadata_paths":      metadataPaths,
		"rounds":              rounds,
		"status":              profile.Status,
	}); err != nil {
		return nil, err
	}
	return &profile, nil
}

func roundMetric(value float64) float64 {
	return float64(int(value*1_000_000+0.5)) / 1_000_000
}

func writeJSON(path string, value any) error {
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	return os.WriteFile(path, data, 0o644)
}
