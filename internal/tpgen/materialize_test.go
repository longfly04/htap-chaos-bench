package tpgen

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"htap-chaos-bench/internal/dataset"
	benchruntime "htap-chaos-bench/internal/runtime"
	"htap-chaos-bench/internal/scenario"
)

func TestMaterializeTPDeterministic(t *testing.T) {
	datasetRoot := t.TempDir()
	runDirA := filepath.Join(t.TempDir(), "run-a")
	runDirB := filepath.Join(t.TempDir(), "run-b")
	if err := os.MkdirAll(filepath.Join(datasetRoot, "tp", "seeds"), 0o755); err != nil {
		t.Fatalf("mkdir seed dir: %v", err)
	}
	if err := os.MkdirAll(filepath.Join(runDirA, "derived"), 0o755); err != nil {
		t.Fatalf("mkdir runDirA: %v", err)
	}
	if err := os.MkdirAll(filepath.Join(runDirB, "derived"), 0o755); err != nil {
		t.Fatalf("mkdir runDirB: %v", err)
	}

	datasetYAML := "dataset_id: job\nsnapshot_id: snap-1\nschema_graph_source: schema\nstats_source: stats\ntp_seed_dir: tp/seeds\nhot_object_rules: modulo\nfreshness_probe: probes/freshness.sql\n"
	if err := os.WriteFile(filepath.Join(datasetRoot, "dataset.yaml"), []byte(datasetYAML), 0o644); err != nil {
		t.Fatalf("write dataset.yaml: %v", err)
	}
	seedSQL := "SELECT 1;\n"
	if err := os.WriteFile(filepath.Join(datasetRoot, "tp", "seeds", "seed1.sql"), []byte(seedSQL), 0o644); err != nil {
		t.Fatalf("write seed sql: %v", err)
	}

	pack, err := dataset.LoadPack(datasetRoot)
	if err != nil {
		t.Fatalf("load pack: %v", err)
	}
	manifest := benchruntime.Manifest{Values: map[string]string{"RUN_ID": "run-1", "TP_PRESSURE": "medium", "SEED": "1"}}
	spec := scenario.Scenario{
		System:   "pg-like",
		Dataset:  "job",
		Snapshot: "snap-1",
		Budget:   "moderate",
		TP: scenario.TPConfig{
			Profile:     "generated",
			Concurrency: 4,
			Terminals:   4,
			RateCap:     0,
			Intensity:   scenario.TPIntensity{BatchSize: 128},
			Skew:        scenario.TPSkew{Mode: "hotspot", HotModulus: 64, HotRemainder: 1},
			Burst:       scenario.TPBurst{Mode: "steady"},
		},
		Chaos: scenario.ChaosConfig{Mode: "none"},
		Drift: scenario.DriftConfig{DataFactor: 0, WorkloadFactor: 0},
		Seed:  1,
	}

	request := MaterializeRequest{Manifest: manifest, Scenario: spec, DatasetPack: pack, DatasetRoot: datasetRoot}
	request.RunDir = runDirA
	if err := MaterializeTP(request); err != nil {
		t.Fatalf("materialize A: %v", err)
	}
	request.RunDir = runDirB
	if err := MaterializeTP(request); err != nil {
		t.Fatalf("materialize B: %v", err)
	}

	sqlA, err := os.ReadFile(filepath.Join(runDirA, "derived", "tp-template-resolved.sql"))
	if err != nil {
		t.Fatalf("read sql A: %v", err)
	}
	sqlB, err := os.ReadFile(filepath.Join(runDirB, "derived", "tp-template-resolved.sql"))
	if err != nil {
		t.Fatalf("read sql B: %v", err)
	}
	if string(sqlA) != string(sqlB) {
		t.Fatalf("resolved SQL mismatch")
	}

	profileA, err := os.ReadFile(filepath.Join(runDirA, "derived", "tp-profile.json"))
	if err != nil {
		t.Fatalf("read profile A: %v", err)
	}
	profileB, err := os.ReadFile(filepath.Join(runDirB, "derived", "tp-profile.json"))
	if err != nil {
		t.Fatalf("read profile B: %v", err)
	}
	if string(profileA) != string(profileB) {
		t.Fatalf("profile mismatch")
	}
}

func TestMaterializeTPWritesPressureControls(t *testing.T) {
	datasetRoot := t.TempDir()
	runDir := filepath.Join(t.TempDir(), "run")
	if err := os.MkdirAll(filepath.Join(datasetRoot, "tp", "seeds"), 0o755); err != nil {
		t.Fatalf("mkdir seed dir: %v", err)
	}
	if err := os.MkdirAll(filepath.Join(runDir, "derived"), 0o755); err != nil {
		t.Fatalf("mkdir run dir: %v", err)
	}

	datasetYAML := "dataset_id: job\nsnapshot_id: snap-1\nschema_graph_source: schema\nstats_source: stats\ntp_seed_dir: tp/seeds\nhot_object_rules: modulo\nfreshness_probe: probes/freshness.sql\n"
	if err := os.WriteFile(filepath.Join(datasetRoot, "dataset.yaml"), []byte(datasetYAML), 0o644); err != nil {
		t.Fatalf("write dataset.yaml: %v", err)
	}
	if err := os.WriteFile(filepath.Join(datasetRoot, "tp", "seeds", "seed1.sql"), []byte("SELECT 1;\n"), 0o644); err != nil {
		t.Fatalf("write seed sql: %v", err)
	}

	pack, err := dataset.LoadPack(datasetRoot)
	if err != nil {
		t.Fatalf("load pack: %v", err)
	}
	manifest := benchruntime.Manifest{Values: map[string]string{
		"RUN_ID":                    "run-2",
		"TP_PRESSURE":               "high",
		"SEED":                      "7",
		"DURATION_SECONDS":          "90",
		"JOB_TP_REPORT_INTERVAL":    "5",
		"AP_CLASS":                  "sort-heavy",
		"OVERLAP":                   "ap-first",
		"AP_TERMINALS":              "2",
		"AP_BURST_INTERVAL_SECONDS": "11",
	}}
	spec := scenario.Scenario{
		System:   "pg-like",
		Dataset:  "job",
		Snapshot: "snap-1",
		Budget:   "tight",
		TP: scenario.TPConfig{
			Profile:     "generated",
			Concurrency: 6,
			Terminals:   9,
			RateCap:     120,
			Intensity:   scenario.TPIntensity{BatchSize: 256},
			Skew:        scenario.TPSkew{Mode: "hotspot", HotModulus: 32, HotRemainder: 5},
			Burst:       scenario.TPBurst{Mode: "steady"},
		},
		AP: scenario.APConfig{
			Class:                "sort-heavy",
			Arrival:              "repeated-burst",
			Terminals:            3,
			BurstIntervalSeconds: 7,
		},
		Chaos: scenario.ChaosConfig{Mode: "none"},
		Drift: scenario.DriftConfig{DataFactor: 0, WorkloadFactor: 0},
		Seed:  7,
	}

	if err := MaterializeTP(MaterializeRequest{
		Manifest:    manifest,
		Scenario:    spec,
		DatasetPack: pack,
		DatasetRoot: datasetRoot,
		RunDir:      runDir,
	}); err != nil {
		t.Fatalf("materialize: %v", err)
	}

	var profile TPProfile
	profileBytes, err := os.ReadFile(filepath.Join(runDir, "derived", "tp-profile.json"))
	if err != nil {
		t.Fatalf("read profile: %v", err)
	}
	if err := json.Unmarshal(profileBytes, &profile); err != nil {
		t.Fatalf("unmarshal profile: %v", err)
	}
	if profile.Threads != 6 {
		t.Fatalf("threads = %d, want 6", profile.Threads)
	}
	if profile.Terminals != 9 {
		t.Fatalf("terminals = %d, want 9", profile.Terminals)
	}
	if profile.RateCap != 120 {
		t.Fatalf("rate_cap = %d, want 120", profile.RateCap)
	}
	if profile.DurationSeconds != 90 {
		t.Fatalf("duration_seconds = %d, want 90", profile.DurationSeconds)
	}
	if profile.ReportInterval != 5 {
		t.Fatalf("report_interval = %d, want 5", profile.ReportInterval)
	}

	var apProfile APProfile
	apProfileBytes, err := os.ReadFile(filepath.Join(runDir, "derived", "ap-profile.json"))
	if err != nil {
		t.Fatalf("read ap profile: %v", err)
	}
	if err := json.Unmarshal(apProfileBytes, &apProfile); err != nil {
		t.Fatalf("unmarshal ap profile: %v", err)
	}
	if apProfile.Class != "sort-heavy" {
		t.Fatalf("ap class = %q, want sort-heavy", apProfile.Class)
	}
	if apProfile.Arrival != "repeated-burst" {
		t.Fatalf("ap arrival = %q, want repeated-burst", apProfile.Arrival)
	}
	if apProfile.Terminals != 3 {
		t.Fatalf("ap terminals = %d, want 3", apProfile.Terminals)
	}
	if apProfile.BurstIntervalSeconds != 7 {
		t.Fatalf("ap burst interval = %d, want 7", apProfile.BurstIntervalSeconds)
	}

	envBytes, err := os.ReadFile(filepath.Join(runDir, "derived", "tp-profile.env"))
	if err != nil {
		t.Fatalf("read env: %v", err)
	}
	envText := string(envBytes)
	for _, expected := range []string{
		"JOB_TP_THREADS=6\n",
		"JOB_TP_TERMINALS=9\n",
		"JOB_TP_RATE_CAP=120\n",
		"JOB_TP_BATCH_SIZE=256\n",
		"JOB_TP_HOT_MODULUS=32\n",
		"JOB_TP_HOT_REMAINDER=5\n",
		"AP_CLASS=sort-heavy\n",
		"AP_TERMINALS=3\n",
		"WORKLOAD_OVERLAP=repeated-burst\n",
		"AP_BURST_INTERVAL_SECONDS=7\n",
		"CHAOS_MODE=none\n",
		"CHAOS_PRIMITIVE=none\n",
	} {
		if !strings.Contains(envText, expected) {
			t.Fatalf("expected env to contain %q, got %q", expected, envText)
		}
	}
}

func TestMaterializeTPWritesFreshnessProfile(t *testing.T) {
	datasetRoot := t.TempDir()
	runDir := filepath.Join(t.TempDir(), "run-freshness")
	if err := os.MkdirAll(filepath.Join(datasetRoot, "tp", "seeds"), 0o755); err != nil {
		t.Fatalf("mkdir seed dir: %v", err)
	}
	if err := os.MkdirAll(filepath.Join(datasetRoot, "probes"), 0o755); err != nil {
		t.Fatalf("mkdir probes dir: %v", err)
	}
	if err := os.MkdirAll(filepath.Join(runDir, "derived"), 0o755); err != nil {
		t.Fatalf("mkdir run dir: %v", err)
	}

	datasetYAML := "dataset_id: job\nsnapshot_id: snap-1\nschema_graph_source: schema\nstats_source: stats\ntp_seed_dir: tp/seeds\nhot_object_rules: movie_freshness modulo hotspot on movie_id\nfreshness_probe: probes/freshness.sql\n"
	if err := os.WriteFile(filepath.Join(datasetRoot, "dataset.yaml"), []byte(datasetYAML), 0o644); err != nil {
		t.Fatalf("write dataset.yaml: %v", err)
	}
	if err := os.WriteFile(filepath.Join(datasetRoot, "tp", "seeds", "seed1.sql"), []byte("SELECT 1;\n"), 0o644); err != nil {
		t.Fatalf("write seed sql: %v", err)
	}
	probeSQL := "select :'probe_id' as probe_id, :'query_class' as query_class, :'probe_phase' as probe_phase, format('movie_id %% %s = %s', :hot_modulus, :hot_remainder) as target_range, 1 as touched_rows, 1 as min_epoch, 2 as max_epoch, now() as latest_touch_ts, 0 as latest_lag_ms;\n"
	if err := os.WriteFile(filepath.Join(datasetRoot, "probes", "freshness.sql"), []byte(probeSQL), 0o644); err != nil {
		t.Fatalf("write freshness probe: %v", err)
	}

	pack, err := dataset.LoadPack(datasetRoot)
	if err != nil {
		t.Fatalf("load pack: %v", err)
	}
	manifest := benchruntime.Manifest{Values: map[string]string{
		"RUN_ID":             "run-freshness",
		"TP_PRESSURE":        "medium",
		"SEED":               "6",
		"HTAP_CHECK_ENABLED": "true",
		"HTAP_CHECK_TYPE":    "query-oriented",
	}}
	spec := scenario.Scenario{
		System:   "pg-like",
		Dataset:  "job",
		Snapshot: "snap-1",
		Budget:   "moderate",
		TP: scenario.TPConfig{
			Profile:     "generated",
			Concurrency: 4,
			Terminals:   4,
			RateCap:     0,
			Intensity:   scenario.TPIntensity{BatchSize: 128},
			Skew:        scenario.TPSkew{Mode: "hotspot", HotModulus: 64, HotRemainder: 1},
			Burst:       scenario.TPBurst{Mode: "steady"},
		},
		AP: scenario.APConfig{
			Class:                "sort-heavy",
			Arrival:              "tp-first",
			Terminals:            1,
			BurstIntervalSeconds: 5,
		},
		HTAPCheck: scenario.HTAPCheckConfig{
			Enabled: true,
			Type:    "query-oriented",
		},
		Chaos: scenario.ChaosConfig{Mode: "none"},
		Drift: scenario.DriftConfig{DataFactor: 0, WorkloadFactor: 0},
		Seed:  6,
	}

	if err := MaterializeTP(MaterializeRequest{
		Manifest:    manifest,
		Scenario:    spec,
		DatasetPack: pack,
		DatasetRoot: datasetRoot,
		RunDir:      runDir,
	}); err != nil {
		t.Fatalf("materialize: %v", err)
	}

	var freshnessProfile FreshnessProfile
	freshnessBytes, err := os.ReadFile(filepath.Join(runDir, "derived", "freshness-profile.json"))
	if err != nil {
		t.Fatalf("read freshness profile: %v", err)
	}
	if err := json.Unmarshal(freshnessBytes, &freshnessProfile); err != nil {
		t.Fatalf("unmarshal freshness profile: %v", err)
	}
	if freshnessProfile.QueryClass != "sort-heavy" {
		t.Fatalf("freshness query class = %q, want sort-heavy", freshnessProfile.QueryClass)
	}
	if freshnessProfile.TargetRange != "movie_id % 64 = 1" {
		t.Fatalf("freshness target range = %q, want movie_id %% 64 = 1", freshnessProfile.TargetRange)
	}
	if freshnessProfile.MaterializedPath != "derived/freshness-probe.sql" {
		t.Fatalf("freshness materialized path = %q, want derived/freshness-probe.sql", freshnessProfile.MaterializedPath)
	}

	probeBytes, err := os.ReadFile(filepath.Join(runDir, "derived", "freshness-probe.sql"))
	if err != nil {
		t.Fatalf("read freshness probe: %v", err)
	}
	if string(probeBytes) != probeSQL {
		t.Fatalf("freshness probe mismatch")
	}

	envBytes, err := os.ReadFile(filepath.Join(runDir, "derived", "tp-profile.env"))
	if err != nil {
		t.Fatalf("read env: %v", err)
	}
	envText := string(envBytes)
	for _, expected := range []string{
		"HTAP_CHECK_ENABLED=true\n",
		"HTAP_CHECK_TYPE=query-oriented\n",
		"FRESHNESS_PROBE_ID=job-sort-heavy-freshness\n",
		"FRESHNESS_QUERY_CLASS=sort-heavy\n",
		"FRESHNESS_TARGET_RANGE='movie_id % 64 = 1'\n",
	} {
		if !strings.Contains(envText, expected) {
			t.Fatalf("expected env to contain %q, got %q", expected, envText)
		}
	}
}

func TestMaterializeTPWritesSyncLatencyProfile(t *testing.T) {
	datasetRoot := t.TempDir()
	runDir := filepath.Join(t.TempDir(), "run-sync-latency")
	if err := os.MkdirAll(filepath.Join(datasetRoot, "tp", "seeds"), 0o755); err != nil {
		t.Fatalf("mkdir seed dir: %v", err)
	}
	if err := os.MkdirAll(filepath.Join(datasetRoot, "probes"), 0o755); err != nil {
		t.Fatalf("mkdir probes dir: %v", err)
	}
	if err := os.MkdirAll(filepath.Join(runDir, "derived"), 0o755); err != nil {
		t.Fatalf("mkdir run dir: %v", err)
	}

	datasetYAML := "dataset_id: job\nsnapshot_id: snap-1\nschema_graph_source: schema\nstats_source: stats\ntp_seed_dir: tp/seeds\nhot_object_rules: movie_freshness modulo hotspot on movie_id\nfreshness_probe: probes/freshness.sql\nsync_latency_probe: probes/sync-latency.sql\n"
	if err := os.WriteFile(filepath.Join(datasetRoot, "dataset.yaml"), []byte(datasetYAML), 0o644); err != nil {
		t.Fatalf("write dataset.yaml: %v", err)
	}
	if err := os.WriteFile(filepath.Join(datasetRoot, "tp", "seeds", "seed1.sql"), []byte("SELECT 1;\n"), 0o644); err != nil {
		t.Fatalf("write seed sql: %v", err)
	}
	probeSQL := "select :'probe_id' as probe_id, :'query_class' as query_class, :'probe_phase' as probe_phase, :target_movie_id::bigint as target_movie_id, epoch as observed_epoch, last_touch_ts as observed_touch_ts, 0::bigint as observed_lag_ms from movie_freshness where movie_id = :target_movie_id;\n"
	if err := os.WriteFile(filepath.Join(datasetRoot, "probes", "sync-latency.sql"), []byte(probeSQL), 0o644); err != nil {
		t.Fatalf("write sync latency probe: %v", err)
	}

	pack, err := dataset.LoadPack(datasetRoot)
	if err != nil {
		t.Fatalf("load pack: %v", err)
	}
	manifest := benchruntime.Manifest{Values: map[string]string{
		"RUN_ID":                        "run-sync-latency",
		"TP_PRESSURE":                   "medium",
		"SEED":                          "8",
		"HTAP_CHECK_ENABLED":            "true",
		"HTAP_CHECK_TYPE":               "sync-latency",
		"SYNC_LATENCY_POLL_INTERVAL_MS": "25",
		"SYNC_LATENCY_TIMEOUT_MS":       "1500",
	}}
	spec := scenario.Scenario{
		System:   "pg-like",
		Dataset:  "job",
		Snapshot: "snap-1",
		Budget:   "moderate",
		TP: scenario.TPConfig{
			Profile:     "generated",
			Concurrency: 4,
			Terminals:   4,
			RateCap:     0,
			Intensity:   scenario.TPIntensity{BatchSize: 128},
			Skew:        scenario.TPSkew{Mode: "hotspot", HotModulus: 64, HotRemainder: 1},
			Burst:       scenario.TPBurst{Mode: "steady"},
		},
		AP: scenario.APConfig{
			Class:                "sort-heavy",
			Arrival:              "tp-first",
			Terminals:            1,
			BurstIntervalSeconds: 5,
		},
		HTAPCheck: scenario.HTAPCheckConfig{
			Enabled: true,
			Type:    "sync-latency",
		},
		Chaos: scenario.ChaosConfig{Mode: "none"},
		Drift: scenario.DriftConfig{DataFactor: 0, WorkloadFactor: 0},
		Seed:  8,
	}

	if err := MaterializeTP(MaterializeRequest{
		Manifest:    manifest,
		Scenario:    spec,
		DatasetPack: pack,
		DatasetRoot: datasetRoot,
		RunDir:      runDir,
	}); err != nil {
		t.Fatalf("materialize: %v", err)
	}

	var syncLatencyProfile SyncLatencyProfile
	syncLatencyBytes, err := os.ReadFile(filepath.Join(runDir, "derived", "sync-latency-profile.json"))
	if err != nil {
		t.Fatalf("read sync latency profile: %v", err)
	}
	if err := json.Unmarshal(syncLatencyBytes, &syncLatencyProfile); err != nil {
		t.Fatalf("unmarshal sync latency profile: %v", err)
	}
	if syncLatencyProfile.QueryClass != "sort-heavy" {
		t.Fatalf("sync latency query class = %q, want sort-heavy", syncLatencyProfile.QueryClass)
	}
	if syncLatencyProfile.TargetRange != "movie_id % 64 = 1" {
		t.Fatalf("sync latency target range = %q, want movie_id %% 64 = 1", syncLatencyProfile.TargetRange)
	}
	if syncLatencyProfile.MaterializedPath != "derived/sync-latency-probe.sql" {
		t.Fatalf("sync latency materialized path = %q, want derived/sync-latency-probe.sql", syncLatencyProfile.MaterializedPath)
	}
	if syncLatencyProfile.PollIntervalMs != 25 {
		t.Fatalf("sync latency poll interval = %d, want 25", syncLatencyProfile.PollIntervalMs)
	}
	if syncLatencyProfile.TimeoutMs != 1500 {
		t.Fatalf("sync latency timeout = %d, want 1500", syncLatencyProfile.TimeoutMs)
	}

	probeBytes, err := os.ReadFile(filepath.Join(runDir, "derived", "sync-latency-probe.sql"))
	if err != nil {
		t.Fatalf("read sync latency probe: %v", err)
	}
	if string(probeBytes) != probeSQL {
		t.Fatalf("sync latency probe mismatch")
	}

	envBytes, err := os.ReadFile(filepath.Join(runDir, "derived", "tp-profile.env"))
	if err != nil {
		t.Fatalf("read env: %v", err)
	}
	envText := string(envBytes)
	for _, expected := range []string{
		"HTAP_CHECK_ENABLED=true\n",
		"HTAP_CHECK_TYPE=sync-latency\n",
		"SYNC_LATENCY_PROBE_ID=job-sort-heavy-sync-latency\n",
		"SYNC_LATENCY_QUERY_CLASS=sort-heavy\n",
		"SYNC_LATENCY_TARGET_RANGE='movie_id % 64 = 1'\n",
		"SYNC_LATENCY_POLL_INTERVAL_MS=25\n",
		"SYNC_LATENCY_TIMEOUT_MS=1500\n",
	} {
		if !strings.Contains(envText, expected) {
			t.Fatalf("expected env to contain %q, got %q", expected, envText)
		}
	}
}

func TestMaterializeTPWritesWorkloadDriftArtifacts(t *testing.T) {
	datasetRoot := t.TempDir()
	runDir := filepath.Join(t.TempDir(), "run-workload-drift")
	if err := os.MkdirAll(filepath.Join(datasetRoot, "tp", "seeds"), 0o755); err != nil {
		t.Fatalf("mkdir seed dir: %v", err)
	}
	if err := os.MkdirAll(filepath.Join(datasetRoot, "queries", "ap"), 0o755); err != nil {
		t.Fatalf("mkdir ap dir: %v", err)
	}
	if err := os.MkdirAll(filepath.Join(datasetRoot, "queries"), 0o755); err != nil {
		t.Fatalf("mkdir queries dir: %v", err)
	}
	if err := os.MkdirAll(filepath.Join(datasetRoot, "metadata"), 0o755); err != nil {
		t.Fatalf("mkdir metadata dir: %v", err)
	}
	if err := os.MkdirAll(filepath.Join(runDir, "derived"), 0o755); err != nil {
		t.Fatalf("mkdir run dir: %v", err)
	}

	datasetYAML := "dataset_id: job\nsnapshot_id: snap-1\nschema_graph_source: schema\nstats_source: stats\ntp_seed_dir: tp/seeds\nhot_object_rules: movie_freshness modulo hotspot on movie_id\nap_classes_file: queries/classes.yaml\nquery_feature_bins: metadata/query_feature_bins.json\n"
	if err := os.WriteFile(filepath.Join(datasetRoot, "dataset.yaml"), []byte(datasetYAML), 0o644); err != nil {
		t.Fatalf("write dataset.yaml: %v", err)
	}
	if err := os.WriteFile(filepath.Join(datasetRoot, "metadata", "query_feature_bins.json"), []byte("{\n  \"query_class\": [\"sort-heavy\", \"hash-heavy\", \"mixed\"]\n}\n"), 0o644); err != nil {
		t.Fatalf("write query_feature_bins.json: %v", err)
	}
	if err := os.WriteFile(filepath.Join(datasetRoot, "tp", "seeds", "seed1.sql"), []byte("SELECT 1;\n"), 0o644); err != nil {
		t.Fatalf("write seed sql: %v", err)
	}
	classesYAML := "sort-heavy:\n  - queries/ap/sort-heavy-q001.sql\nhash-heavy:\n  - queries/ap/hash-heavy-q001.sql\nmixed:\n  - queries/ap/mixed-q001.sql\n"
	if err := os.WriteFile(filepath.Join(datasetRoot, "queries", "classes.yaml"), []byte(classesYAML), 0o644); err != nil {
		t.Fatalf("write classes.yaml: %v", err)
	}
	for path, sqlText := range map[string]string{
		"sort-heavy-q001.sql": "SELECT * FROM company_type ct JOIN movie_companies mc ON mc.company_type_id = ct.id JOIN title t ON t.id = mc.movie_id JOIN movie_freshness mf ON mf.movie_id = t.id WHERE mf.hot_flag = true AND mf.epoch >= 0 ORDER BY t.production_year DESC LIMIT 10;\n",
		"hash-heavy-q001.sql": "SELECT * FROM cast_info ci JOIN name n ON n.id = ci.person_id JOIN role_type rt ON rt.id = ci.role_id JOIN title t ON t.id = ci.movie_id JOIN movie_freshness mf ON mf.movie_id = t.id WHERE mf.hot_flag = true AND mf.epoch >= 0 GROUP BY mf.movie_id LIMIT 10;\n",
		"mixed-q001.sql":      "SELECT * FROM cast_info ci JOIN name n ON n.id = ci.person_id JOIN title t ON t.id = ci.movie_id JOIN movie_companies mc ON mc.movie_id = t.id JOIN company_type ct ON ct.id = mc.company_type_id JOIN movie_freshness mf ON mf.movie_id = t.id WHERE mf.hot_flag = true AND mf.epoch >= 0 ORDER BY t.title LIMIT 10;\n",
	} {
		if err := os.WriteFile(filepath.Join(datasetRoot, "queries", "ap", path), []byte(sqlText), 0o644); err != nil {
			t.Fatalf("write %s: %v", path, err)
		}
	}

	pack, err := dataset.LoadPack(datasetRoot)
	if err != nil {
		t.Fatalf("load pack: %v", err)
	}
	manifest := benchruntime.Manifest{Values: map[string]string{
		"RUN_ID":                     "run-workload-drift",
		"TP_PRESSURE":                "medium",
		"SEED":                       "9",
		"WORKLOAD_DRIFT_FACTOR":      "0.5",
		"WORKLOAD_DRIFT_SAMPLE_SIZE": "6",
	}}
	spec := scenario.Scenario{
		System:   "pg-like",
		Dataset:  "job",
		Snapshot: "snap-1",
		Budget:   "moderate",
		TP: scenario.TPConfig{
			Profile:     "generated",
			Concurrency: 4,
			Terminals:   4,
			RateCap:     0,
			Intensity:   scenario.TPIntensity{BatchSize: 128},
			Skew:        scenario.TPSkew{Mode: "hotspot", HotModulus: 64, HotRemainder: 1},
			Burst:       scenario.TPBurst{Mode: "steady"},
		},
		AP: scenario.APConfig{
			Class:                "sort-heavy",
			Arrival:              "tp-first",
			Terminals:            1,
			BurstIntervalSeconds: 5,
		},
		Chaos: scenario.ChaosConfig{Mode: "none"},
		Drift: scenario.DriftConfig{DataFactor: 0, WorkloadFactor: 0.5},
		Observe: scenario.ObserveConfig{
			ExportPGStats:          true,
			SamplingIntervalSeconds: 7,
			MetricsProfile:          "mixed-chaos",
			RenderPlots:             true,
			PlotProfile:             "chaos-heavy",
			PlotDPI:                 360,
			CompareGroup:            "phase5-workload-drift",
		},
		Seed:  9,
	}

	if err := MaterializeTP(MaterializeRequest{
		Manifest:    manifest,
		Scenario:    spec,
		DatasetPack: pack,
		DatasetRoot: datasetRoot,
		RunDir:      runDir,
	}); err != nil {
		t.Fatalf("materialize: %v", err)
	}

	var workloadDriftProfile WorkloadDriftProfile
	profileBytes, err := os.ReadFile(filepath.Join(runDir, "derived", "workload-drift-profile.json"))
	if err != nil {
		t.Fatalf("read workload drift profile: %v", err)
	}
	if err := json.Unmarshal(profileBytes, &workloadDriftProfile); err != nil {
		t.Fatalf("unmarshal workload drift profile: %v", err)
	}
	if !workloadDriftProfile.Enabled {
		t.Fatalf("workload drift enabled = false, want true")
	}
	if workloadDriftProfile.BaseQueryClass != "sort-heavy" {
		t.Fatalf("workload drift base class = %q, want sort-heavy", workloadDriftProfile.BaseQueryClass)
	}
	if workloadDriftProfile.SampleSize != 6 {
		t.Fatalf("workload drift sample size = %d, want 6", workloadDriftProfile.SampleSize)
	}
	if workloadDriftProfile.RealizedWorkloadFactor <= 0 {
		t.Fatalf("workload drift realized factor = %f, want > 0", workloadDriftProfile.RealizedWorkloadFactor)
	}

	for _, path := range []string{
		"workload-drift-factor.json",
		"query-feature-map.json",
		"query-feature-dist.before.json",
		"query-feature-dist.after.json",
		"query-drift-sample.sql",
	} {
		if _, err := os.Stat(filepath.Join(runDir, "derived", path)); err != nil {
			t.Fatalf("stat %s: %v", path, err)
		}
	}

	driftSampleBytes, err := os.ReadFile(filepath.Join(runDir, "derived", "query-drift-sample.sql"))
	if err != nil {
		t.Fatalf("read workload drift sample: %v", err)
	}
	driftSampleText := string(driftSampleBytes)
	if !strings.Contains(driftSampleText, "workload drift sample") {
		t.Fatalf("workload drift sample sql missing annotation")
	}
	if !strings.Contains(driftSampleText, "hash-heavy-q001") {
		t.Fatalf("workload drift sample sql = %q, want drifted query reference", driftSampleText)
	}

	envBytes, err := os.ReadFile(filepath.Join(runDir, "derived", "tp-profile.env"))
	if err != nil {
		t.Fatalf("read env: %v", err)
	}
	envText := string(envBytes)
	for _, expected := range []string{
		"WORKLOAD_DRIFT_ENABLED=true\n",
		"DRIFT_FEATURE_SCOPE='query_class|table_count|join_count|predicate_count|tables|predicates'\n",
		"WORKLOAD_DRIFT_FACTOR=0.5\n",
		"WORKLOAD_DRIFT_BASE_CLASS=sort-heavy\n",
		"WORKLOAD_DRIFT_SAMPLE_SIZE=6\n",
		"WORKLOAD_DRIFT_STATUS=materialized\n",
		"EXPORT_PG_STATS=true\n",
		"OBSERVE_SAMPLING_INTERVAL_SECONDS=7\n",
		"OBSERVE_METRICS_PROFILE=mixed-chaos\n",
		"AUTO_RENDER_PLOTS=true\n",
		"PLOT_PROFILE=chaos-heavy\n",
		"PLOT_DPI=360\n",
		"OBSERVE_COMPARE_GROUP=phase5-workload-drift\n",
	} {
		if !strings.Contains(envText, expected) {
			t.Fatalf("expected env to contain %q, got %q", expected, envText)
		}
	}
}

func TestMaterializeTPWritesChaosProfile(t *testing.T) {
	datasetRoot := t.TempDir()
	runDir := filepath.Join(t.TempDir(), "run-chaos")
	if err := os.MkdirAll(filepath.Join(datasetRoot, "tp", "seeds"), 0o755); err != nil {
		t.Fatalf("mkdir seed dir: %v", err)
	}
	if err := os.MkdirAll(filepath.Join(runDir, "derived"), 0o755); err != nil {
		t.Fatalf("mkdir run dir: %v", err)
	}

	datasetYAML := "dataset_id: job\nsnapshot_id: snap-1\nschema_graph_source: schema\nstats_source: stats\ntp_seed_dir: tp/seeds\nhot_object_rules: movie_freshness modulo hotspot on movie_id\nfreshness_probe: probes/freshness.sql\n"
	if err := os.WriteFile(filepath.Join(datasetRoot, "dataset.yaml"), []byte(datasetYAML), 0o644); err != nil {
		t.Fatalf("write dataset.yaml: %v", err)
	}
	if err := os.WriteFile(filepath.Join(datasetRoot, "tp", "seeds", "seed1.sql"), []byte("SELECT 1;\n"), 0o644); err != nil {
		t.Fatalf("write seed sql: %v", err)
	}

	pack, err := dataset.LoadPack(datasetRoot)
	if err != nil {
		t.Fatalf("load pack: %v", err)
	}
	manifest := benchruntime.Manifest{Values: map[string]string{
		"RUN_ID":           "run-chaos",
		"TP_PRESSURE":      "medium",
		"SEED":             "3",
		"DURATION_SECONDS": "60",
	}}
	spec := scenario.Scenario{
		System:   "pg-like",
		Dataset:  "job",
		Snapshot: "snap-1",
		Budget:   "moderate",
		TP: scenario.TPConfig{
			Profile:     "generated",
			Concurrency: 4,
			Terminals:   4,
			RateCap:     0,
			Intensity:   scenario.TPIntensity{BatchSize: 128},
			Skew:        scenario.TPSkew{Mode: "hotspot", HotModulus: 64, HotRemainder: 1},
			Burst:       scenario.TPBurst{Mode: "steady"},
		},
		AP: scenario.APConfig{
			Class:                "sort-heavy",
			Arrival:              "tp-first",
			Terminals:            1,
			BurstIntervalSeconds: 5,
		},
		Chaos: scenario.ChaosConfig{
			Mode:              "single-fault",
			Stage:             "mixed-steady-state",
			StartAfterSeconds: 10,
			DurationSeconds:   15,
			Seed:              3,
			Injections: []scenario.ChaosInjection{{
				ID:             "waitxact_hotspot_l1",
				Family:         "lock-path",
				Primitive:      "wait_xact",
				TargetSelector: "tp-hotspot/movie_freshness",
				Intensity:      "L1",
				Params: scenario.ChaosParams{
					Jobs:            1,
					LockHoldSeconds: 15,
					Fixture:         true,
				},
			}},
		},
		Drift: scenario.DriftConfig{DataFactor: 0, WorkloadFactor: 0},
		Seed:  3,
	}

	if err := MaterializeTP(MaterializeRequest{
		Manifest:    manifest,
		Scenario:    spec,
		DatasetPack: pack,
		DatasetRoot: datasetRoot,
		RunDir:      runDir,
	}); err != nil {
		t.Fatalf("materialize: %v", err)
	}

	var chaosProfile ChaosProfile
	chaosBytes, err := os.ReadFile(filepath.Join(runDir, "derived", "chaos-profile.json"))
	if err != nil {
		t.Fatalf("read chaos profile: %v", err)
	}
	if err := json.Unmarshal(chaosBytes, &chaosProfile); err != nil {
		t.Fatalf("unmarshal chaos profile: %v", err)
	}
	if chaosProfile.Mode != "single-fault" {
		t.Fatalf("chaos mode = %q, want single-fault", chaosProfile.Mode)
	}
	if chaosProfile.Stage != "mixed-steady-state" {
		t.Fatalf("chaos stage = %q, want mixed-steady-state", chaosProfile.Stage)
	}
	if chaosProfile.Injection == nil || chaosProfile.Injection.Primitive != "wait_xact" {
		t.Fatalf("chaos injection primitive = %#v, want wait_xact", chaosProfile.Injection)
	}
	if chaosProfile.Injection.LockHoldSeconds != 15 {
		t.Fatalf("chaos lock hold seconds = %d, want 15", chaosProfile.Injection.LockHoldSeconds)
	}
	if !chaosProfile.Injection.Fixture {
		t.Fatalf("chaos fixture = false, want true")
	}

	var selector TargetSelectorProfile
	selectorBytes, err := os.ReadFile(filepath.Join(runDir, "derived", "target-selector.json"))
	if err != nil {
		t.Fatalf("read target selector: %v", err)
	}
	if err := json.Unmarshal(selectorBytes, &selector); err != nil {
		t.Fatalf("unmarshal target selector: %v", err)
	}
	if selector.SelectionExpr != "movie_id % 64 = 1" {
		t.Fatalf("selection expr = %q, want movie_id %% 64 = 1", selector.SelectionExpr)
	}
	if selector.Source != "tpgen-hotspot-selector" {
		t.Fatalf("selector source = %q, want tpgen-hotspot-selector", selector.Source)
	}

	envBytes, err := os.ReadFile(filepath.Join(runDir, "derived", "tp-profile.env"))
	if err != nil {
		t.Fatalf("read env: %v", err)
	}
	envText := string(envBytes)
	for _, expected := range []string{
		"CHAOS_MODE=single-fault\n",
		"CHAOS_STAGE=mixed-steady-state\n",
		"CHAOS_START_AFTER_SECONDS=10\n",
		"CHAOS_DURATION_SECONDS=15\n",
		"CHAOS_PRIMITIVE=wait_xact\n",
		"CHAOS_TARGET_SELECTOR=tp-hotspot/movie_freshness\n",
		"CHAOS_JOBS=1\n",
		"CHAOS_LOCK_HOLD_SECONDS=15\n",
		"CHAOS_FIXTURE=true\n",
	} {
		if !strings.Contains(envText, expected) {
			t.Fatalf("expected env to contain %q, got %q", expected, envText)
		}
	}
}

func TestMaterializeTPWritesDeadlockChaosProfile(t *testing.T) {
	datasetRoot := t.TempDir()
	runDir := filepath.Join(t.TempDir(), "run-deadlock")
	if err := os.MkdirAll(filepath.Join(datasetRoot, "tp", "seeds"), 0o755); err != nil {
		t.Fatalf("mkdir seed dir: %v", err)
	}
	if err := os.MkdirAll(filepath.Join(runDir, "derived"), 0o755); err != nil {
		t.Fatalf("mkdir run dir: %v", err)
	}

	datasetYAML := "dataset_id: job\nsnapshot_id: snap-1\nschema_graph_source: schema\nstats_source: stats\ntp_seed_dir: tp/seeds\nhot_object_rules: movie_freshness modulo hotspot on movie_id\nfreshness_probe: probes/freshness.sql\n"
	if err := os.WriteFile(filepath.Join(datasetRoot, "dataset.yaml"), []byte(datasetYAML), 0o644); err != nil {
		t.Fatalf("write dataset.yaml: %v", err)
	}
	if err := os.WriteFile(filepath.Join(datasetRoot, "tp", "seeds", "seed1.sql"), []byte("SELECT 1;\n"), 0o644); err != nil {
		t.Fatalf("write seed sql: %v", err)
	}

	pack, err := dataset.LoadPack(datasetRoot)
	if err != nil {
		t.Fatalf("load pack: %v", err)
	}
	manifest := benchruntime.Manifest{Values: map[string]string{
		"RUN_ID":           "run-deadlock",
		"TP_PRESSURE":      "medium",
		"SEED":             "4",
		"DURATION_SECONDS": "60",
	}}
	spec := scenario.Scenario{
		System:   "pg-like",
		Dataset:  "job",
		Snapshot: "snap-1",
		Budget:   "moderate",
		TP: scenario.TPConfig{
			Profile:     "generated",
			Concurrency: 4,
			Terminals:   4,
			RateCap:     0,
			Intensity:   scenario.TPIntensity{BatchSize: 128},
			Skew:        scenario.TPSkew{Mode: "hotspot", HotModulus: 64, HotRemainder: 1},
			Burst:       scenario.TPBurst{Mode: "steady"},
		},
		AP: scenario.APConfig{
			Class:                "sort-heavy",
			Arrival:              "tp-first",
			Terminals:            1,
			BurstIntervalSeconds: 5,
		},
		Chaos: scenario.ChaosConfig{
			Mode:              "single-fault",
			Stage:             "mixed-steady-state",
			StartAfterSeconds: 10,
			DurationSeconds:   15,
			Seed:              4,
			Injections: []scenario.ChaosInjection{{
				ID:             "cross_update_deadlock",
				Family:         "lock-path",
				Primitive:      "deadlock_pair",
				TargetSelector: "fixture_rows:2",
				Intensity:      "L1",
				Params: scenario.ChaosParams{
					Jobs: 1,
				},
			}},
		},
		Drift: scenario.DriftConfig{DataFactor: 0, WorkloadFactor: 0},
		Seed:  4,
	}

	if err := MaterializeTP(MaterializeRequest{
		Manifest:    manifest,
		Scenario:    spec,
		DatasetPack: pack,
		DatasetRoot: datasetRoot,
		RunDir:      runDir,
	}); err != nil {
		t.Fatalf("materialize: %v", err)
	}

	var chaosProfile ChaosProfile
	chaosBytes, err := os.ReadFile(filepath.Join(runDir, "derived", "chaos-profile.json"))
	if err != nil {
		t.Fatalf("read chaos profile: %v", err)
	}
	if err := json.Unmarshal(chaosBytes, &chaosProfile); err != nil {
		t.Fatalf("unmarshal chaos profile: %v", err)
	}
	if chaosProfile.Injection == nil || chaosProfile.Injection.Primitive != "deadlock_pair" {
		t.Fatalf("chaos injection primitive = %#v, want deadlock_pair", chaosProfile.Injection)
	}
	if chaosProfile.Injection.Jobs != 1 {
		t.Fatalf("chaos jobs = %d, want 1", chaosProfile.Injection.Jobs)
	}

	var selector TargetSelectorProfile
	selectorBytes, err := os.ReadFile(filepath.Join(runDir, "derived", "target-selector.json"))
	if err != nil {
		t.Fatalf("read target selector: %v", err)
	}
	if err := json.Unmarshal(selectorBytes, &selector); err != nil {
		t.Fatalf("unmarshal target selector: %v", err)
	}
	if selector.SelectionExpr != "fixture_rows = 2" {
		t.Fatalf("selection expr = %q, want fixture_rows = 2", selector.SelectionExpr)
	}
	if selector.Source != "fixture-row-selector" {
		t.Fatalf("selector source = %q, want fixture-row-selector", selector.Source)
	}

	envBytes, err := os.ReadFile(filepath.Join(runDir, "derived", "tp-profile.env"))
	if err != nil {
		t.Fatalf("read env: %v", err)
	}
	envText := string(envBytes)
	for _, expected := range []string{
		"CHAOS_MODE=single-fault\n",
		"CHAOS_PRIMITIVE=deadlock_pair\n",
		"CHAOS_TARGET_SELECTOR=fixture_rows:2\n",
		"CHAOS_JOBS=1\n",
	} {
		if !strings.Contains(envText, expected) {
			t.Fatalf("expected env to contain %q, got %q", expected, envText)
		}
	}
}

func TestMaterializeTPWritesSpillChaosProfile(t *testing.T) {
	datasetRoot := t.TempDir()
	runDir := filepath.Join(t.TempDir(), "run-spill")
	if err := os.MkdirAll(filepath.Join(datasetRoot, "tp", "seeds"), 0o755); err != nil {
		t.Fatalf("mkdir seed dir: %v", err)
	}
	if err := os.MkdirAll(filepath.Join(runDir, "derived"), 0o755); err != nil {
		t.Fatalf("mkdir run dir: %v", err)
	}

	datasetYAML := "dataset_id: job\nsnapshot_id: snap-1\nschema_graph_source: schema\nstats_source: stats\ntp_seed_dir: tp/seeds\nhot_object_rules: movie_freshness modulo hotspot on movie_id\nfreshness_probe: probes/freshness.sql\n"
	if err := os.WriteFile(filepath.Join(datasetRoot, "dataset.yaml"), []byte(datasetYAML), 0o644); err != nil {
		t.Fatalf("write dataset.yaml: %v", err)
	}
	if err := os.WriteFile(filepath.Join(datasetRoot, "tp", "seeds", "seed1.sql"), []byte("SELECT 1;\n"), 0o644); err != nil {
		t.Fatalf("write seed sql: %v", err)
	}

	pack, err := dataset.LoadPack(datasetRoot)
	if err != nil {
		t.Fatalf("load pack: %v", err)
	}
	manifest := benchruntime.Manifest{Values: map[string]string{
		"RUN_ID":           "run-spill",
		"TP_PRESSURE":      "medium",
		"SEED":             "5",
		"DURATION_SECONDS": "60",
	}}
	spec := scenario.Scenario{
		System:   "pg-like",
		Dataset:  "job",
		Snapshot: "snap-1",
		Budget:   "moderate",
		TP: scenario.TPConfig{
			Profile:     "generated",
			Concurrency: 4,
			Terminals:   4,
			RateCap:     0,
			Intensity:   scenario.TPIntensity{BatchSize: 128},
			Skew:        scenario.TPSkew{Mode: "hotspot", HotModulus: 64, HotRemainder: 1},
			Burst:       scenario.TPBurst{Mode: "steady"},
		},
		AP: scenario.APConfig{
			Class:                "sort-heavy",
			Arrival:              "tp-first",
			Terminals:            1,
			BurstIntervalSeconds: 5,
		},
		Chaos: scenario.ChaosConfig{
			Mode:              "single-fault",
			Stage:             "mixed-steady-state",
			StartAfterSeconds: 10,
			DurationSeconds:   15,
			Seed:              5,
			Injections: []scenario.ChaosInjection{{
				ID:             "spill_sort_l1",
				Family:         "memory-path",
				Primitive:      "spill_pressure",
				TargetSelector: "ap_query_class:sort-heavy",
				Intensity:      "L1",
				Params: scenario.ChaosParams{
					Workers:       2,
					SessionMemory: "64kB",
					Rate:          1.0,
				},
			}},
		},
		Drift: scenario.DriftConfig{DataFactor: 0, WorkloadFactor: 0},
		Seed:  5,
	}

	if err := MaterializeTP(MaterializeRequest{
		Manifest:    manifest,
		Scenario:    spec,
		DatasetPack: pack,
		DatasetRoot: datasetRoot,
		RunDir:      runDir,
	}); err != nil {
		t.Fatalf("materialize: %v", err)
	}

	var chaosProfile ChaosProfile
	chaosBytes, err := os.ReadFile(filepath.Join(runDir, "derived", "chaos-profile.json"))
	if err != nil {
		t.Fatalf("read chaos profile: %v", err)
	}
	if err := json.Unmarshal(chaosBytes, &chaosProfile); err != nil {
		t.Fatalf("unmarshal chaos profile: %v", err)
	}
	if chaosProfile.Injection == nil || chaosProfile.Injection.Primitive != "spill_pressure" {
		t.Fatalf("chaos injection primitive = %#v, want spill_pressure", chaosProfile.Injection)
	}
	if chaosProfile.Injection.Workers != 2 {
		t.Fatalf("chaos workers = %d, want 2", chaosProfile.Injection.Workers)
	}
	if chaosProfile.Injection.SessionMemory != "64kB" {
		t.Fatalf("chaos session memory = %q, want 64kB", chaosProfile.Injection.SessionMemory)
	}
	if chaosProfile.Injection.Rate != 1.0 {
		t.Fatalf("chaos rate = %v, want 1.0", chaosProfile.Injection.Rate)
	}

	var selector TargetSelectorProfile
	selectorBytes, err := os.ReadFile(filepath.Join(runDir, "derived", "target-selector.json"))
	if err != nil {
		t.Fatalf("read target selector: %v", err)
	}
	if err := json.Unmarshal(selectorBytes, &selector); err != nil {
		t.Fatalf("unmarshal target selector: %v", err)
	}
	if selector.SelectionExpr != "ap.class = sort-heavy" {
		t.Fatalf("selection expr = %q, want ap.class = sort-heavy", selector.SelectionExpr)
	}
	if selector.Source != "ap-class-selector" {
		t.Fatalf("selector source = %q, want ap-class-selector", selector.Source)
	}

	envBytes, err := os.ReadFile(filepath.Join(runDir, "derived", "tp-profile.env"))
	if err != nil {
		t.Fatalf("read env: %v", err)
	}
	envText := string(envBytes)
	for _, expected := range []string{
		"CHAOS_MODE=single-fault\n",
		"CHAOS_PRIMITIVE=spill_pressure\n",
		"CHAOS_TARGET_SELECTOR=ap_query_class:sort-heavy\n",
		"CHAOS_WORKERS=2\n",
		"CHAOS_SESSION_MEMORY=64kB\n",
		"CHAOS_RATE=1\n",
	} {
		if !strings.Contains(envText, expected) {
			t.Fatalf("expected env to contain %q, got %q", expected, envText)
		}
	}
}
