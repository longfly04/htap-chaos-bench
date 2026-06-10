package dataset

import (
	"fmt"
	"os"
	"path/filepath"

	"gopkg.in/yaml.v3"
)

type Pack struct {
	DatasetID               string `yaml:"dataset_id" json:"dataset_id"`
	SnapshotID              string `yaml:"snapshot_id" json:"snapshot_id"`
	SchemaGraphSource       string `yaml:"schema_graph_source" json:"schema_graph_source"`
	StatsSource             string `yaml:"stats_source" json:"stats_source"`
	TPSeedDir               string `yaml:"tp_seed_dir" json:"tp_seed_dir"`
	HotObjectRules          string `yaml:"hot_object_rules" json:"hot_object_rules"`
	APClassesFile           string `yaml:"ap_classes_file" json:"ap_classes_file"`
	QueryFeatureBins        string `yaml:"query_feature_bins" json:"query_feature_bins"`
	DriftApplicableColumns  string `yaml:"drift_applicable_columns" json:"drift_applicable_columns"`
	ColumnNames             string `yaml:"column_names" json:"column_names"`
	SupportsDrift           bool   `yaml:"supports_drift" json:"supports_drift"`
	FreshnessProbe          string `yaml:"freshness_probe" json:"freshness_probe"`
	SyncLatencyProbe        string `yaml:"sync_latency_probe" json:"sync_latency_probe"`
}

func LoadPack(root string) (Pack, error) {
	path := filepath.Join(root, "dataset.yaml")
	data, err := os.ReadFile(path)
	if err != nil {
		return Pack{}, err
	}
	var pack Pack
	if err := yaml.Unmarshal(data, &pack); err != nil {
		return Pack{}, err
	}
	if err := pack.Validate(); err != nil {
		return Pack{}, err
	}
	return pack, nil
}

func (p Pack) Validate() error {
	if p.DatasetID == "" {
		return fmt.Errorf("dataset.dataset_id is required")
	}
	if p.SnapshotID == "" {
		return fmt.Errorf("dataset.snapshot_id is required")
	}
	if p.TPSeedDir == "" {
		return fmt.Errorf("dataset.tp_seed_dir is required")
	}
	return nil
}
