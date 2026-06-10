package tpgen

import "htap-chaos-bench/internal/dataset"

type SchemaGraphSource struct {
	DatasetID         string `json:"dataset_id"`
	SnapshotID        string `json:"snapshot_id"`
	SchemaGraphSource string `json:"schema_graph_source"`
	StatsSource       string `json:"stats_source"`
}

func GraphSource(pack dataset.Pack) SchemaGraphSource {
	return SchemaGraphSource{
		DatasetID:         pack.DatasetID,
		SnapshotID:        pack.SnapshotID,
		SchemaGraphSource: pack.SchemaGraphSource,
		StatsSource:       pack.StatsSource,
	}
}
