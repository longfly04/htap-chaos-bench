package tpgen

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	chaospkg "htap-chaos-bench/internal/chaos"
	"htap-chaos-bench/internal/dataset"
	driftpkg "htap-chaos-bench/internal/drift"
	benchruntime "htap-chaos-bench/internal/runtime"
	"htap-chaos-bench/internal/scenario"
)

type MaterializeRequest struct {
	Manifest    benchruntime.Manifest
	Scenario    scenario.Scenario
	DatasetPack dataset.Pack
	DatasetRoot string
	RunDir      string
}

type TPProfile struct {
	TemplateID      string            `json:"template_id"`
	TemplateName    string            `json:"template_name"`
	TemplatePath    string            `json:"template_path"`
	DatasetID       string            `json:"dataset_id"`
	SnapshotID      string            `json:"snapshot_id"`
	RunID           string            `json:"run_id"`
	Seed            int               `json:"seed"`
	Pressure        string            `json:"pressure"`
	Driver          string            `json:"driver"`
	Threads         int               `json:"threads"`
	Terminals       int               `json:"terminals"`
	RateCap         int               `json:"rate_cap"`
	BatchSize       int               `json:"batch_size"`
	HotModulus      int               `json:"hot_modulus"`
	HotRemainder    int               `json:"hot_remainder"`
	SelectorMode    string            `json:"selector_mode"`
	BurstMode       string            `json:"burst_mode"`
	DurationSeconds int               `json:"duration_seconds"`
	ReportInterval  int               `json:"report_interval"`
	SchemaGraph     SchemaGraphSource `json:"schema_graph"`
}

type APProfile struct {
	Class                string `json:"class"`
	Arrival              string `json:"arrival"`
	Terminals            int    `json:"terminals"`
	Parallelism          int    `json:"parallelism"`
	BurstIntervalSeconds int    `json:"burst_interval_seconds"`
}

type HTAPCheckProfile struct {
	Enabled bool   `json:"enabled"`
	Type    string `json:"type"`
}

type FreshnessProfile struct {
	ProbeID          string `json:"probe_id"`
	QueryClass       string `json:"query_class"`
	TargetRange      string `json:"target_range"`
	ProbeSource      string `json:"probe_source"`
	MaterializedPath string `json:"materialized_path"`
	HotModulus       int    `json:"hot_modulus"`
	HotRemainder     int    `json:"hot_remainder"`
	Status           string `json:"status"`
}

type SyncLatencyProfile struct {
	ProbeID          string `json:"probe_id"`
	QueryClass       string `json:"query_class"`
	TargetRange      string `json:"target_range"`
	ProbeSource      string `json:"probe_source"`
	MaterializedPath string `json:"materialized_path"`
	HotModulus       int    `json:"hot_modulus"`
	HotRemainder     int    `json:"hot_remainder"`
	PollIntervalMs   int    `json:"poll_interval_ms"`
	TimeoutMs        int    `json:"timeout_ms"`
	Status           string `json:"status"`
}

type ThermalProfile struct {
	Enabled             bool                  `json:"enabled"`
	Profile             string                `json:"profile"`
	Model               string                `json:"model"`
	PrimaryStateTable   string                `json:"primary_state_table"`
	AmbientBaseline     float64               `json:"ambient_baseline"`
	CoolingRate         float64               `json:"cooling_rate"`
	ObservationStepS    int                   `json:"observation_step_seconds"`
	HorizonS            int                   `json:"horizon_seconds"`
	SteadyState         string                `json:"steady_state"`
	TransientState      string                `json:"transient_state"`
	TargetTemperature   float64               `json:"target_temperature"`
	DriftRate           float64               `json:"drift_rate"`
	HeatBudget          float64               `json:"heat_budget"`
	TableCount          int                   `json:"table_count"`
	TracePath           string                `json:"trace_path"`
	TableProfilePath    string                `json:"table_profile_path"`
	Tables              []ThermalTableProfile `json:"tables"`
	Status              string                `json:"status"`
}

type ThermalTableProfile struct {
	Name               string  `json:"name"`
	Role               string  `json:"role"`
	InitialTemperature float64 `json:"initial_temperature"`
	TargetTemperature  float64 `json:"target_temperature"`
	HeatCapacity       float64 `json:"heat_capacity"`
	AccessWeight       float64 `json:"access_weight"`
	IOWeight           float64 `json:"io_weight"`
	Coupling           float64 `json:"coupling"`
}

type ChaosProfile struct {
	Mode              string                 `json:"mode"`
	Stage             string                 `json:"stage"`
	SafetyLevel       string                 `json:"safety_level"`
	CleanupProfile    string                 `json:"cleanup_profile"`
	StartAfterSeconds int                    `json:"start_after_seconds"`
	DurationSeconds   int                    `json:"duration_seconds"`
	Seed              int                    `json:"seed"`
	Injection         *ChaosInjectionProfile `json:"injection,omitempty"`
}

type ChaosInjectionProfile struct {
	ID              string  `json:"id"`
	Family          string  `json:"family"`
	Primitive       string  `json:"primitive"`
	TargetSelector  string  `json:"target_selector"`
	Intensity       string  `json:"intensity"`
	Jobs            int     `json:"jobs"`
	LockHoldSeconds int     `json:"lock_hold_seconds"`
	Fixture         bool    `json:"fixture"`
	Workers         int     `json:"workers"`
	SessionMemory   string  `json:"session_memory"`
	Rate            float64 `json:"rate"`
}

type HotspotSelector struct {
	Mode         string `json:"mode"`
	HotModulus   int    `json:"hot_modulus"`
	HotRemainder int    `json:"hot_remainder"`
	TargetRule   string `json:"target_rule"`
}

type TargetSelectorProfile struct {
	Mode          string `json:"mode"`
	DatasetID     string `json:"dataset_id"`
	TargetRule    string `json:"target_rule"`
	SelectionExpr string `json:"selection_expr"`
	HotModulus    int    `json:"hot_modulus"`
	HotRemainder  int    `json:"hot_remainder"`
	Source        string `json:"source"`
}

type CardinalityProfile struct {
	TemplateID      string `json:"template_id"`
	TemplateName    string `json:"template_name"`
	PredicateClass  string `json:"predicate_class"`
	SelectionWindow string `json:"selection_window"`
	BatchSize       int    `json:"batch_size"`
	Status          string `json:"status"`
}

type ResolvedScenario struct {
	RunID         string                      `json:"run_id"`
	System        string                      `json:"system"`
	Dataset       string                      `json:"dataset"`
	Snapshot      string                      `json:"snapshot"`
	BudgetTier    string                      `json:"budget_tier"`
	Seed          int                         `json:"seed"`
	TP            TPProfile                   `json:"tp"`
	AP            *APProfile                  `json:"ap,omitempty"`
	Thermal       *ThermalProfile             `json:"thermal,omitempty"`
	HTAPCheck     *HTAPCheckProfile           `json:"htap_check,omitempty"`
	Freshness     *FreshnessProfile           `json:"freshness,omitempty"`
	SyncLatency   *SyncLatencyProfile         `json:"sync_latency,omitempty"`
	WorkloadDrift *WorkloadDriftProfile       `json:"workload_drift,omitempty"`
	DataDrift     *driftpkg.DataDriftProfile  `json:"data_drift,omitempty"`
	Chaos         *ChaosProfile               `json:"chaos,omitempty"`
	CleanupPolicy *chaospkg.CleanupPolicy     `json:"cleanup_policy,omitempty"`
	Raw           scenario.Scenario           `json:"raw"`
}

func MaterializeTP(request MaterializeRequest) error {
	seedDir := filepath.Join(request.DatasetRoot, filepath.FromSlash(request.DatasetPack.TPSeedDir))
	templates, err := LoadSeedTemplates(seedDir)
	if err != nil {
		return err
	}

	seed := request.Manifest.Int("SEED", 0)
	if seed == 0 {
		seed = request.Scenario.Seed
	}
	if seed == 0 {
		seed = 1
	}
	template, err := ChooseUpdateTemplate(templates, seed)
	if err != nil {
		return err
	}
	content, err := os.ReadFile(template.Path)
	if err != nil {
		return err
	}

	derivedDir := filepath.Join(request.RunDir, "derived")
	if err := os.MkdirAll(derivedDir, 0o755); err != nil {
		return err
	}

	batchSize := request.Scenario.TP.Intensity.BatchSize
	if batchSize <= 0 {
		batchSize = manifestIntOrEnv(request.Manifest, "JOB_TP_BATCH_SIZE", 128)
	}
	hotModulus := request.Scenario.TP.Skew.HotModulus
	if hotModulus <= 0 {
		hotModulus = manifestIntOrEnv(request.Manifest, "JOB_TP_HOT_MODULUS", 64)
	}
	hotRemainder := request.Scenario.TP.Skew.HotRemainder
	if hotModulus > 0 {
		hotRemainder = hotRemainder % hotModulus
	}
	threads := request.Scenario.TP.Concurrency
	if threads <= 0 {
		threads = manifestIntOrEnv(request.Manifest, "JOB_TP_THREADS", 4)
	}
	terminals := request.Scenario.TP.Terminals
	if terminals <= 0 {
		terminals = threads
	}
	rateCap := request.Scenario.TP.RateCap
	if rateCap <= 0 {
		rateCap = manifestIntOrEnv(request.Manifest, "JOB_TP_RATE_CAP", request.Manifest.Int("TP_RATE_CAP", 0))
	}
	durationSeconds := manifestIntOrEnv(request.Manifest, "DURATION_SECONDS", 60)
	if durationSeconds <= 0 {
		durationSeconds = 60
	}
	reportInterval := manifestIntOrEnv(request.Manifest, "JOB_TP_REPORT_INTERVAL", 1)
	if reportInterval <= 0 {
		reportInterval = 1
	}
	tpDriver := strings.ToLower(strings.TrimSpace(firstNonEmpty(request.Scenario.TP.Driver, manifestStringOrEnv(request.Manifest, "JOB_TP_DRIVER", manifestStringOrEnv(request.Manifest, "TP_DRIVER", "pgbench")))))
	if tpDriver == "" {
		tpDriver = "pgbench"
	}
	switch tpDriver {
	case "pgbench", "sysbench":
	default:
		return fmt.Errorf("unsupported TP driver %q", tpDriver)
	}

	apClass := strings.TrimSpace(firstNonEmpty(request.Scenario.AP.Class, request.Manifest.Get("AP_CLASS")))
	apArrival := strings.TrimSpace(firstNonEmpty(request.Scenario.AP.Arrival, request.Manifest.Get("OVERLAP"), "tp-first"))
	apTerminals := request.Scenario.AP.Terminals
	if apTerminals <= 0 {
		apTerminals = manifestIntOrEnv(request.Manifest, "AP_TERMINALS", 1)
		if apTerminals <= 0 {
			apTerminals = 1
		}
	}
	apParallelism := request.Scenario.AP.Parallelism
	if apParallelism <= 0 {
		apParallelism = manifestIntOrEnv(request.Manifest, "AP_PARALLELISM", 0)
	}
	apBurstInterval := request.Scenario.AP.BurstIntervalSeconds
	if apBurstInterval <= 0 {
		apBurstInterval = manifestIntOrEnv(request.Manifest, "AP_BURST_INTERVAL_SECONDS", 5)
		if apBurstInterval <= 0 {
			apBurstInterval = 5
		}
	}
	exportPGStats := manifestBoolOrEnv(request.Manifest, "EXPORT_PG_STATS", request.Scenario.Observe.ExportPGStats)
	observeSamplingIntervalSeconds := request.Scenario.Observe.SamplingIntervalSeconds
	if observeSamplingIntervalSeconds <= 0 {
		observeSamplingIntervalSeconds = manifestIntOrEnv(request.Manifest, "OBSERVE_SAMPLING_INTERVAL_SECONDS", 5)
		if observeSamplingIntervalSeconds <= 0 {
			observeSamplingIntervalSeconds = 5
		}
	}
	observeMetricsProfile := strings.TrimSpace(firstNonEmpty(request.Scenario.Observe.MetricsProfile, manifestStringOrEnv(request.Manifest, "OBSERVE_METRICS_PROFILE", "mixed-default")))
	autoRenderPlots := manifestBoolOrEnv(request.Manifest, "AUTO_RENDER_PLOTS", request.Scenario.Observe.RenderPlots)
	plotProfile := strings.TrimSpace(firstNonEmpty(request.Scenario.Observe.PlotProfile, manifestStringOrEnv(request.Manifest, "PLOT_PROFILE", "mixed-default")))
	plotDPI := request.Scenario.Observe.PlotDPI
	if plotDPI <= 0 {
		plotDPI = manifestIntOrEnv(request.Manifest, "PLOT_DPI", 300)
		if plotDPI <= 0 {
			plotDPI = 300
		}
	}
	observeCompareGroup := strings.TrimSpace(firstNonEmpty(request.Scenario.Observe.CompareGroup, request.Manifest.Get("OBSERVE_COMPARE_GROUP")))
	featureScope := driftpkg.NormalizeFeatureScope(request.Scenario.Drift.FeatureScope)
	if len(request.Scenario.Drift.FeatureScope) == 0 {
		if parsed := driftpkg.ParseFeatureScope(request.Manifest.Get("DRIFT_FEATURE_SCOPE")); len(parsed) > 0 {
			featureScope = parsed
		}
	}
	thermalProfile, err := materializeThermalProfile(request.Scenario.Thermal, derivedDir)
	if err != nil {
		return err
	}
	cleanupProfile := strings.TrimSpace(manifestStringOrEnv(request.Manifest, "CHAOS_CLEANUP_PROFILE", "pg-default"))
	safetyLevel := strings.TrimSpace(manifestStringOrEnv(request.Manifest, "CHAOS_SAFETY_LEVEL", "mainline"))
	if err := chaospkg.ValidateSafetyLevel(safetyLevel); err != nil {
		return err
	}

	profile := TPProfile{
		TemplateID:      template.ID,
		TemplateName:    template.Name,
		TemplatePath:    template.Path,
		DatasetID:       request.DatasetPack.DatasetID,
		SnapshotID:      request.DatasetPack.SnapshotID,
		RunID:           request.Manifest.Get("RUN_ID"),
		Seed:            seed,
		Pressure:        request.Manifest.Get("TP_PRESSURE"),
		Driver:          tpDriver,
		Threads:         threads,
		Terminals:       terminals,
		RateCap:         rateCap,
		BatchSize:       batchSize,
		HotModulus:      hotModulus,
		HotRemainder:    hotRemainder,
		SelectorMode:    request.Scenario.TP.Skew.Mode,
		BurstMode:       request.Scenario.TP.Burst.Mode,
		DurationSeconds: durationSeconds,
		ReportInterval:  reportInterval,
		SchemaGraph:     GraphSource(request.DatasetPack),
	}

	hotspotSelector := HotspotSelector{
		Mode:         request.Scenario.TP.Skew.Mode,
		HotModulus:   hotModulus,
		HotRemainder: hotRemainder,
		TargetRule:   request.DatasetPack.HotObjectRules,
	}
	targetSelector := TargetSelectorProfile{
		Mode:          firstNonEmpty(request.Scenario.TP.Skew.Mode, "hotspot"),
		DatasetID:     request.DatasetPack.DatasetID,
		TargetRule:    request.DatasetPack.HotObjectRules,
		SelectionExpr: fmt.Sprintf("movie_id %% %d = %d", hotModulus, hotRemainder),
		HotModulus:    hotModulus,
		HotRemainder:  hotRemainder,
		Source:        "tpgen-hotspot-selector",
	}
	cardinality := CardinalityProfile{
		TemplateID:      template.ID,
		TemplateName:    template.Name,
		PredicateClass:  "modulo-hotspot",
		SelectionWindow: fmt.Sprintf("movie_id %% %d = %d", hotModulus, hotRemainder),
		BatchSize:       batchSize,
		Status:          "first-slice-seed-template",
	}

	var apProfile *APProfile
	if apClass != "" && apClass != "na" {
		apProfile = &APProfile{
			Class:                apClass,
			Arrival:              apArrival,
			Terminals:            apTerminals,
			Parallelism:          apParallelism,
			BurstIntervalSeconds: apBurstInterval,
		}
	}

	htapCheckEnabled := request.Scenario.HTAPCheck.Enabled
	if !htapCheckEnabled {
		htapCheckEnabled = parseBool(request.Manifest.Get("HTAP_CHECK_ENABLED"))
	}
	htapCheckType := strings.TrimSpace(firstNonEmpty(request.Scenario.HTAPCheck.Type, request.Manifest.Get("HTAP_CHECK_TYPE")))
	if htapCheckEnabled && htapCheckType == "" {
		htapCheckType = "query-oriented"
	}
	if !htapCheckEnabled {
		htapCheckType = firstNonEmpty(htapCheckType, "none")
	}
	syncLatencyPollIntervalMs := manifestIntOrEnv(request.Manifest, "SYNC_LATENCY_POLL_INTERVAL_MS", 50)
	if syncLatencyPollIntervalMs <= 0 {
		syncLatencyPollIntervalMs = 50
	}
	syncLatencyTimeoutMs := manifestIntOrEnv(request.Manifest, "SYNC_LATENCY_TIMEOUT_MS", 5000)
	if syncLatencyTimeoutMs <= 0 {
		syncLatencyTimeoutMs = 5000
	}
	dataDriftFactor := request.Scenario.Drift.DataFactor
	if manifestDataDrift := strings.TrimSpace(request.Manifest.Get("DATA_DRIFT_FACTOR")); manifestDataDrift != "" {
		if parsed, err := strconv.ParseFloat(manifestDataDrift, 64); err == nil {
			dataDriftFactor = parsed
		}
	}
	workloadDriftFactor := request.Scenario.Drift.WorkloadFactor
	if manifestWorkloadDrift := strings.TrimSpace(request.Manifest.Get("WORKLOAD_DRIFT_FACTOR")); manifestWorkloadDrift != "" {
		if parsed, err := strconv.ParseFloat(manifestWorkloadDrift, 64); err == nil {
			workloadDriftFactor = parsed
		}
	}
	workloadDriftSampleSize := manifestIntOrEnv(request.Manifest, "WORKLOAD_DRIFT_SAMPLE_SIZE", 6)
	if workloadDriftSampleSize <= 0 {
		workloadDriftSampleSize = 6
	}
	var htapCheckProfile *HTAPCheckProfile
	var freshnessProfile *FreshnessProfile
	var syncLatencyProfile *SyncLatencyProfile
	var workloadDriftProfile *WorkloadDriftProfile
	var dataDriftProfile *driftpkg.DataDriftProfile
	if dataDriftFactor < 0 || dataDriftFactor > 1 {
		return fmt.Errorf("DATA_DRIFT_FACTOR must be within [0,1]")
	}
	if workloadDriftFactor < 0 || workloadDriftFactor > 1 {
		return fmt.Errorf("WORKLOAD_DRIFT_FACTOR must be within [0,1]")
	}
	if htapCheckEnabled {
		htapCheckProfile = &HTAPCheckProfile{
			Enabled: true,
			Type:    htapCheckType,
		}
	}
	if htapCheckEnabled && htapCheckType == "query-oriented" {
		probePath := filepath.Join(request.DatasetRoot, filepath.FromSlash(request.DatasetPack.FreshnessProbe))
		probeContent, err := os.ReadFile(probePath)
		if err != nil {
			return err
		}
		if err := os.WriteFile(filepath.Join(derivedDir, "freshness-probe.sql"), probeContent, 0o644); err != nil {
			return err
		}
		freshnessProfile = &FreshnessProfile{
			ProbeID:          fmt.Sprintf("%s-%s-freshness", request.DatasetPack.DatasetID, firstNonEmpty(apClass, "tp-hotspot")),
			QueryClass:       firstNonEmpty(apClass, "tp-hotspot"),
			TargetRange:      fmt.Sprintf("movie_id %% %d = %d", hotModulus, hotRemainder),
			ProbeSource:      request.DatasetPack.FreshnessProbe,
			MaterializedPath: "derived/freshness-probe.sql",
			HotModulus:       hotModulus,
			HotRemainder:     hotRemainder,
			Status:           "materialized",
		}
	}
	if htapCheckEnabled && htapCheckType == "sync-latency" {
		probeSource := strings.TrimSpace(request.DatasetPack.SyncLatencyProbe)
		if probeSource == "" {
			return fmt.Errorf("dataset.sync_latency_probe is required for htap_check.type=sync-latency")
		}
		probePath := filepath.Join(request.DatasetRoot, filepath.FromSlash(probeSource))
		probeContent, err := os.ReadFile(probePath)
		if err != nil {
			return err
		}
		if err := os.WriteFile(filepath.Join(derivedDir, "sync-latency-probe.sql"), probeContent, 0o644); err != nil {
			return err
		}
		syncLatencyProfile = &SyncLatencyProfile{
			ProbeID:          fmt.Sprintf("%s-%s-sync-latency", request.DatasetPack.DatasetID, firstNonEmpty(apClass, "tp-hotspot")),
			QueryClass:       firstNonEmpty(apClass, "tp-hotspot"),
			TargetRange:      fmt.Sprintf("movie_id %% %d = %d", hotModulus, hotRemainder),
			ProbeSource:      probeSource,
			MaterializedPath: "derived/sync-latency-probe.sql",
			HotModulus:       hotModulus,
			HotRemainder:     hotRemainder,
			PollIntervalMs:   syncLatencyPollIntervalMs,
			TimeoutMs:        syncLatencyTimeoutMs,
			Status:           "materialized",
		}
	}
	if dataDriftFactor > 0 {
		dataDriftProfile, err = driftpkg.MaterializeDataDrift(
			request.DatasetRoot,
			request.DatasetPack,
			derivedDir,
			featureScope,
			dataDriftFactor,
			seed,
		)
		if err != nil {
			return err
		}
	}
	if workloadDriftFactor > 0 {
		if strings.TrimSpace(apClass) == "" || apClass == "na" {
			return fmt.Errorf("AP_CLASS is required when drift.workload_factor > 0")
		}
		workloadDriftProfile, err = materializeWorkloadDrift(
			request.DatasetRoot,
			request.DatasetPack,
			derivedDir,
			apClass,
			featureScope,
			dataDriftFactor,
			workloadDriftFactor,
			workloadDriftSampleSize,
			seed,
		)
		if err != nil {
			return err
		}
	}

	chaosMode := firstNonEmpty(request.Scenario.Chaos.Mode, "none")
	chaosStage := request.Scenario.Chaos.Stage
	chaosStartAfter := request.Scenario.Chaos.StartAfterSeconds
	chaosDuration := request.Scenario.Chaos.DurationSeconds
	chaosSeed := request.Scenario.Chaos.Seed
	if chaosSeed == 0 {
		chaosSeed = seed
	}
	chaosID := ""
	chaosFamily := ""
	chaosPrimitive := "none"
	chaosTargetSelector := ""
	chaosIntensity := ""
	chaosJobs := 0
	chaosLockHoldSeconds := 0
	chaosFixture := false
	chaosWorkers := 0
	chaosSessionMemory := ""
	chaosRate := 0.0
	policySafetyLevel := safetyLevel
	policyCleanupProfile := cleanupProfile
	var chaosProfile *ChaosProfile
	var cleanupPolicy *chaospkg.CleanupPolicy
	if chaosMode != "" && chaosMode != "none" && len(request.Scenario.Chaos.Injections) > 0 {
		injection := request.Scenario.Chaos.Injections[0]
		chaosID = injection.ID
		chaosFamily = injection.Family
		chaosPrimitive = injection.Primitive
		chaosTargetSelector = injection.TargetSelector
		chaosIntensity = injection.Intensity
		chaosJobs = injection.Params.Jobs
		if chaosJobs <= 0 {
			chaosJobs = manifestIntOrEnv(request.Manifest, "JOB_CHAOS_WAIT_JOBS", 1)
		}
		chaosLockHoldSeconds = injection.Params.LockHoldSeconds
		if chaosLockHoldSeconds <= 0 {
			chaosLockHoldSeconds = manifestIntOrEnv(request.Manifest, "JOB_CHAOS_WAIT_LOCK_HOLD_SECONDS", 15)
		}
		chaosFixture = injection.Params.Fixture
		chaosWorkers = injection.Params.Workers
		if chaosWorkers <= 0 {
			chaosWorkers = manifestIntOrEnv(request.Manifest, "JOB_CHAOS_SPILL_WORKERS", 1)
		}
		chaosSessionMemory = strings.TrimSpace(injection.Params.SessionMemory)
		if chaosSessionMemory == "" {
			chaosSessionMemory = manifestStringOrEnv(request.Manifest, "JOB_CHAOS_SPILL_SESSION_MEMORY", "64kB")
		}
		chaosRate = injection.Params.Rate
		if chaosRate <= 0 {
			chaosRate = manifestFloatOrEnv(request.Manifest, "JOB_CHAOS_SPILL_RATE_QPS", 1.0)
		}
		switch chaosPrimitive {
		case "wait_xact":
			if chaosJobs <= 0 {
				chaosJobs = manifestIntOrEnv(request.Manifest, "JOB_CHAOS_WAIT_JOBS", 1)
			}
			if chaosLockHoldSeconds <= 0 {
				chaosLockHoldSeconds = manifestIntOrEnv(request.Manifest, "JOB_CHAOS_WAIT_LOCK_HOLD_SECONDS", 15)
			}
			if chaosDuration <= 0 {
				chaosDuration = manifestIntOrEnv(request.Manifest, "JOB_CHAOS_WAIT_DURATION_SECONDS", 15)
			}
			if chaosDuration < chaosLockHoldSeconds {
				chaosDuration = chaosLockHoldSeconds
			}
		case "deadlock_pair":
			if chaosJobs <= 0 {
				chaosJobs = manifestIntOrEnv(request.Manifest, "JOB_CHAOS_DEADLOCK_JOBS", 1)
			}
			if chaosDuration <= 0 {
				chaosDuration = manifestIntOrEnv(request.Manifest, "JOB_CHAOS_DEADLOCK_DURATION_SECONDS", 15)
			}
			fixtureRows := "2"
			if selector := strings.TrimSpace(chaosTargetSelector); strings.HasPrefix(selector, "fixture_rows:") {
				rows := strings.TrimSpace(strings.TrimPrefix(selector, "fixture_rows:"))
				if rows != "" {
					fixtureRows = rows
				}
			}
			targetSelector = TargetSelectorProfile{
				Mode:          "fixture_rows",
				DatasetID:     request.DatasetPack.DatasetID,
				TargetRule:    firstNonEmpty(chaosTargetSelector, "fixture_rows:2"),
				SelectionExpr: fmt.Sprintf("fixture_rows = %s", fixtureRows),
				Source:        "fixture-row-selector",
			}
		case "spill_pressure":
			if chaosWorkers <= 0 {
				chaosWorkers = manifestIntOrEnv(request.Manifest, "JOB_CHAOS_SPILL_WORKERS", 1)
			}
			if chaosSessionMemory == "" {
				chaosSessionMemory = manifestStringOrEnv(request.Manifest, "JOB_CHAOS_SPILL_SESSION_MEMORY", "64kB")
			}
			if chaosRate <= 0 {
				if parsed, err := strconv.ParseFloat(manifestStringOrEnv(request.Manifest, "JOB_CHAOS_SPILL_RATE_QPS", "1"), 64); err == nil {
					chaosRate = parsed
				}
			}
			if chaosDuration <= 0 {
				chaosDuration = manifestIntOrEnv(request.Manifest, "JOB_CHAOS_SPILL_DURATION_SECONDS", 15)
			}
			targetClass := apClass
			if selector := strings.TrimSpace(chaosTargetSelector); strings.HasPrefix(selector, "ap_query_class:") {
				targetClass = strings.TrimSpace(strings.TrimPrefix(selector, "ap_query_class:"))
			}
			targetClass = firstNonEmpty(targetClass, apClass, "sort-heavy")
			targetSelector = TargetSelectorProfile{
				Mode:          "ap_query_class",
				DatasetID:     request.DatasetPack.DatasetID,
				TargetRule:    firstNonEmpty(chaosTargetSelector, "ap_query_class:sort-heavy"),
				SelectionExpr: fmt.Sprintf("ap.class = %s", targetClass),
				Source:        "ap-class-selector",
			}
		default:
			if chaosDuration <= 0 {
				chaosDuration = manifestIntOrEnv(request.Manifest, "JOB_CHAOS_WAIT_DURATION_SECONDS", 15)
			}
		}
		resolvedPolicy, err := chaospkg.ResolvePrimitivePolicy(chaosPrimitive, safetyLevel, cleanupProfile)
		if err != nil {
			return err
		}
		policySafetyLevel = string(resolvedPolicy.SafetyLevel)
		policyCleanupProfile = resolvedPolicy.CleanupProfile
		resolvedCleanupPolicy := chaospkg.ResolveCleanupPolicy(policyCleanupProfile)
		cleanupPolicy = &resolvedCleanupPolicy
		if chaosFamily == "" {
			chaosFamily = resolvedPolicy.Family
		}
		chaosProfile = &ChaosProfile{
			Mode:              chaosMode,
			Stage:             chaosStage,
			SafetyLevel:       policySafetyLevel,
			CleanupProfile:    policyCleanupProfile,
			StartAfterSeconds: chaosStartAfter,
			DurationSeconds:   chaosDuration,
			Seed:              chaosSeed,
			Injection: &ChaosInjectionProfile{
				ID:              chaosID,
				Family:          chaosFamily,
				Primitive:       chaosPrimitive,
				TargetSelector:  chaosTargetSelector,
				Intensity:       chaosIntensity,
				Jobs:            chaosJobs,
				LockHoldSeconds: chaosLockHoldSeconds,
				Fixture:         chaosFixture,
				Workers:         chaosWorkers,
				SessionMemory:   chaosSessionMemory,
				Rate:            chaosRate,
			},
		}
	}

	resolved := ResolvedScenario{
		RunID:         request.Manifest.Get("RUN_ID"),
		System:        request.Scenario.System,
		Dataset:       request.Scenario.Dataset,
		Snapshot:      request.Scenario.Snapshot,
		BudgetTier:    request.Scenario.Budget,
		Seed:          seed,
		TP:            profile,
		AP:            apProfile,
		Thermal:       thermalProfile,
		HTAPCheck:     htapCheckProfile,
		Freshness:     freshnessProfile,
		SyncLatency:   syncLatencyProfile,
		WorkloadDrift: workloadDriftProfile,
		DataDrift:     dataDriftProfile,
		Chaos:         chaosProfile,
		CleanupPolicy: cleanupPolicy,
		Raw:           request.Scenario,
	}

	if err := os.WriteFile(filepath.Join(derivedDir, "tp-template-resolved.sql"), content, 0o644); err != nil {
		return err
	}
	if err := writeJSON(filepath.Join(derivedDir, "tp-profile.json"), profile); err != nil {
		return err
	}
	if apProfile != nil {
		if err := writeJSON(filepath.Join(derivedDir, "ap-profile.json"), apProfile); err != nil {
			return err
		}
	}
	if thermalProfile != nil {
		if err := writeJSON(filepath.Join(derivedDir, "thermal-profile.json"), thermalProfile); err != nil {
			return err
		}
	}
	if htapCheckProfile != nil {
		if err := writeJSON(filepath.Join(derivedDir, "htap-check.json"), htapCheckProfile); err != nil {
			return err
		}
	}
	if freshnessProfile != nil {
		if err := writeJSON(filepath.Join(derivedDir, "freshness-profile.json"), freshnessProfile); err != nil {
			return err
		}
	}
	if syncLatencyProfile != nil {
		if err := writeJSON(filepath.Join(derivedDir, "sync-latency-profile.json"), syncLatencyProfile); err != nil {
			return err
		}
	}
	if workloadDriftProfile != nil {
		if err := writeJSON(filepath.Join(derivedDir, "workload-drift-profile.json"), workloadDriftProfile); err != nil {
			return err
		}
	}
			if chaosProfile != nil {
			if err := writeJSON(filepath.Join(derivedDir, "chaos-profile.json"), chaosProfile); err != nil {
				return err
			}
			if cleanupPolicy != nil {
				if err := writeJSON(filepath.Join(derivedDir, "cleanup-policy.json"), cleanupPolicy); err != nil {
					return err
				}
			}
		}
	if err := writeJSON(filepath.Join(derivedDir, "hotspot-selector.json"), hotspotSelector); err != nil {
		return err
	}
	if err := writeJSON(filepath.Join(derivedDir, "target-selector.json"), targetSelector); err != nil {
		return err
	}
	if err := writeJSON(filepath.Join(derivedDir, "cardinality-profile.json"), cardinality); err != nil {
		return err
	}
	if err := writeJSON(filepath.Join(derivedDir, "scenario.resolved.json"), resolved); err != nil {
		return err
	}
	if err := writeEnv(filepath.Join(derivedDir, "tp-profile.env"), map[string]string{
		"JOB_TP_DRIVER":                 tpDriver,
		"JOB_TP_THREADS":                fmt.Sprintf("%d", threads),
		"JOB_TP_TERMINALS":              fmt.Sprintf("%d", terminals),
		"JOB_TP_RATE_CAP":               fmt.Sprintf("%d", rateCap),
		"JOB_TP_BATCH_SIZE":             fmt.Sprintf("%d", batchSize),
		"JOB_TP_HOT_MODULUS":            fmt.Sprintf("%d", hotModulus),
		"JOB_TP_HOT_REMAINDER":          fmt.Sprintf("%d", hotRemainder),
		"JOB_TP_TEMPLATE_ID":            template.ID,
		"AP_CLASS":                      firstNonEmpty(apClass, "na"),
		"AP_TERMINALS":                  fmt.Sprintf("%d", apTerminals),
		"AP_PARALLELISM":                fmt.Sprintf("%d", apParallelism),
		"WORKLOAD_OVERLAP":              apArrival,
		"AP_BURST_INTERVAL_SECONDS":     fmt.Sprintf("%d", apBurstInterval),
		"EXPORT_PG_STATS":               fmt.Sprintf("%t", exportPGStats),
		"THERMAL_ENABLED":               fmt.Sprintf("%t", thermalProfile != nil),
		"THERMAL_PROFILE":               thermalValue(thermalProfile, func(profile *ThermalProfile) string { return profile.Profile }),
		"THERMAL_MODEL":                 thermalValue(thermalProfile, func(profile *ThermalProfile) string { return profile.Model }),
		"THERMAL_PRIMARY_TABLE":         thermalValue(thermalProfile, func(profile *ThermalProfile) string { return profile.PrimaryStateTable }),
		"THERMAL_TARGET_TEMPERATURE":    thermalValue(thermalProfile, func(profile *ThermalProfile) string { return formatFloat(profile.TargetTemperature) }),
		"THERMAL_TRANSIENT_STATE":       thermalValue(thermalProfile, func(profile *ThermalProfile) string { return profile.TransientState }),
		"THERMAL_STEADY_STATE":          thermalValue(thermalProfile, func(profile *ThermalProfile) string { return profile.SteadyState }),
		"THERMAL_TRACE_PATH":            thermalValue(thermalProfile, func(profile *ThermalProfile) string { return profile.TracePath }),
		"THERMAL_TABLE_PROFILE_PATH":    thermalValue(thermalProfile, func(profile *ThermalProfile) string { return profile.TableProfilePath }),
			"OBSERVE_SAMPLING_INTERVAL_SECONDS": fmt.Sprintf("%d", observeSamplingIntervalSeconds),
			"OBSERVE_METRICS_PROFILE":       observeMetricsProfile,
			"AUTO_RENDER_PLOTS":             fmt.Sprintf("%t", autoRenderPlots),
			"PLOT_PROFILE":                  plotProfile,
			"PLOT_DPI":                      fmt.Sprintf("%d", plotDPI),
			"OBSERVE_COMPARE_GROUP":         observeCompareGroup,
			"HTAP_CHECK_ENABLED":            fmt.Sprintf("%t", htapCheckEnabled),
		"HTAP_CHECK_TYPE":               htapCheckType,
		"FRESHNESS_PROBE_ID":            freshnessValue(freshnessProfile, func(profile *FreshnessProfile) string { return profile.ProbeID }),
		"FRESHNESS_QUERY_CLASS":         freshnessValue(freshnessProfile, func(profile *FreshnessProfile) string { return profile.QueryClass }),
		"FRESHNESS_TARGET_RANGE":        freshnessValue(freshnessProfile, func(profile *FreshnessProfile) string { return profile.TargetRange }),
		"FRESHNESS_HOT_MODULUS":         fmt.Sprintf("%d", hotModulus),
		"FRESHNESS_HOT_REMAINDER":       fmt.Sprintf("%d", hotRemainder),
		"SYNC_LATENCY_PROBE_ID":         syncLatencyValue(syncLatencyProfile, func(profile *SyncLatencyProfile) string { return profile.ProbeID }),
		"SYNC_LATENCY_QUERY_CLASS":      syncLatencyValue(syncLatencyProfile, func(profile *SyncLatencyProfile) string { return profile.QueryClass }),
		"SYNC_LATENCY_TARGET_RANGE":     syncLatencyValue(syncLatencyProfile, func(profile *SyncLatencyProfile) string { return profile.TargetRange }),
		"SYNC_LATENCY_HOT_MODULUS":      fmt.Sprintf("%d", hotModulus),
		"SYNC_LATENCY_HOT_REMAINDER":    fmt.Sprintf("%d", hotRemainder),
		"SYNC_LATENCY_POLL_INTERVAL_MS": fmt.Sprintf("%d", syncLatencyPollIntervalMs),
		"SYNC_LATENCY_TIMEOUT_MS":       fmt.Sprintf("%d", syncLatencyTimeoutMs),
		"WORKLOAD_DRIFT_ENABLED":        fmt.Sprintf("%t", workloadDriftProfile != nil),
		"DRIFT_FEATURE_SCOPE":           strings.Join(featureScope, "|"),
		"DATA_DRIFT_FACTOR":             formatFloat(dataDriftFactor),
		"WORKLOAD_DRIFT_FACTOR":         formatFloat(workloadDriftFactor),
		"WORKLOAD_DRIFT_REALIZED_FACTOR": workloadDriftValue(workloadDriftProfile, func(profile *WorkloadDriftProfile) string {
			return formatFloat(profile.RealizedWorkloadFactor)
		}),
		"WORKLOAD_DRIFT_BASE_CLASS": workloadDriftValue(workloadDriftProfile, func(profile *WorkloadDriftProfile) string {
			return profile.BaseQueryClass
		}),
		"WORKLOAD_DRIFT_SAMPLE_SIZE": workloadDriftValue(workloadDriftProfile, func(profile *WorkloadDriftProfile) string {
			return fmt.Sprintf("%d", profile.SampleSize)
		}),
		"WORKLOAD_DRIFT_STATUS": workloadDriftValue(workloadDriftProfile, func(profile *WorkloadDriftProfile) string {
			return profile.Status
		}),
		"CHAOS_MODE":                chaosMode,
		"CHAOS_STAGE":               chaosStage,
		"CHAOS_SAFETY_LEVEL":        policySafetyLevel,
		"CHAOS_CLEANUP_PROFILE":     policyCleanupProfile,
		"CHAOS_START_AFTER_SECONDS": fmt.Sprintf("%d", chaosStartAfter),
		"CHAOS_DURATION_SECONDS":    fmt.Sprintf("%d", chaosDuration),
		"CHAOS_SEED":                fmt.Sprintf("%d", chaosSeed),
		"CHAOS_ID":                  chaosID,
		"CHAOS_FAMILY":              chaosFamily,
		"CHAOS_PRIMITIVE":           chaosPrimitive,
		"CHAOS_TARGET_SELECTOR":     chaosTargetSelector,
		"CHAOS_INTENSITY":           chaosIntensity,
		"CHAOS_JOBS":                fmt.Sprintf("%d", chaosJobs),
		"CHAOS_LOCK_HOLD_SECONDS":   fmt.Sprintf("%d", chaosLockHoldSeconds),
		"CHAOS_FIXTURE":             fmt.Sprintf("%t", chaosFixture),
		"CHAOS_WORKERS":             fmt.Sprintf("%d", chaosWorkers),
		"CHAOS_SESSION_MEMORY":      chaosSessionMemory,
		"CHAOS_RATE":                formatFloat(chaosRate),
	}); err != nil {
		return err
	}

	return nil
}

func writeJSON(path string, value any) error {
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	return os.WriteFile(path, data, 0o644)
}

func writeEnv(path string, values map[string]string) error {
	data := make([]byte, 0)
	keys := []string{
		"JOB_TP_DRIVER",
		"JOB_TP_THREADS",
		"JOB_TP_TERMINALS",
		"JOB_TP_RATE_CAP",
		"JOB_TP_BATCH_SIZE",
		"JOB_TP_HOT_MODULUS",
		"JOB_TP_HOT_REMAINDER",
		"JOB_TP_TEMPLATE_ID",
		"AP_CLASS",
		"AP_TERMINALS",
		"AP_PARALLELISM",
		"WORKLOAD_OVERLAP",
		"AP_BURST_INTERVAL_SECONDS",
		"EXPORT_PG_STATS",
		"THERMAL_ENABLED",
		"THERMAL_PROFILE",
		"THERMAL_MODEL",
		"THERMAL_PRIMARY_TABLE",
		"THERMAL_TARGET_TEMPERATURE",
		"THERMAL_TRANSIENT_STATE",
		"THERMAL_STEADY_STATE",
		"THERMAL_TRACE_PATH",
		"THERMAL_TABLE_PROFILE_PATH",
			"OBSERVE_SAMPLING_INTERVAL_SECONDS",
			"OBSERVE_METRICS_PROFILE",
			"AUTO_RENDER_PLOTS",
			"PLOT_PROFILE",
			"PLOT_DPI",
			"OBSERVE_COMPARE_GROUP",
			"HTAP_CHECK_ENABLED",
		"HTAP_CHECK_TYPE",
		"FRESHNESS_PROBE_ID",
		"FRESHNESS_QUERY_CLASS",
		"FRESHNESS_TARGET_RANGE",
		"FRESHNESS_HOT_MODULUS",
		"FRESHNESS_HOT_REMAINDER",
		"SYNC_LATENCY_PROBE_ID",
		"SYNC_LATENCY_QUERY_CLASS",
		"SYNC_LATENCY_TARGET_RANGE",
		"SYNC_LATENCY_HOT_MODULUS",
		"SYNC_LATENCY_HOT_REMAINDER",
		"SYNC_LATENCY_POLL_INTERVAL_MS",
		"SYNC_LATENCY_TIMEOUT_MS",
		"WORKLOAD_DRIFT_ENABLED",
		"DRIFT_FEATURE_SCOPE",
		"DATA_DRIFT_FACTOR",
		"WORKLOAD_DRIFT_FACTOR",
		"WORKLOAD_DRIFT_REALIZED_FACTOR",
		"WORKLOAD_DRIFT_BASE_CLASS",
		"WORKLOAD_DRIFT_SAMPLE_SIZE",
		"WORKLOAD_DRIFT_STATUS",
		"CHAOS_MODE",
		"CHAOS_STAGE",
		"CHAOS_SAFETY_LEVEL",
		"CHAOS_CLEANUP_PROFILE",
		"CHAOS_START_AFTER_SECONDS",
		"CHAOS_DURATION_SECONDS",
		"CHAOS_SEED",
		"CHAOS_ID",
		"CHAOS_FAMILY",
		"CHAOS_PRIMITIVE",
		"CHAOS_TARGET_SELECTOR",
		"CHAOS_INTENSITY",
		"CHAOS_JOBS",
		"CHAOS_LOCK_HOLD_SECONDS",
		"CHAOS_FIXTURE",
		"CHAOS_WORKERS",
		"CHAOS_SESSION_MEMORY",
		"CHAOS_RATE",
	}
	for _, key := range keys {
		if value, ok := values[key]; ok {
			data = append(data, []byte(fmt.Sprintf("%s=%s\n", key, shellValue(value)))...)
		}
	}
	return os.WriteFile(path, data, 0o644)
}

func shellValue(value string) string {
	if value == "" {
		return value
	}
	const safe = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./:-+=,%@"
	if strings.IndexFunc(value, func(r rune) bool {
		return !strings.ContainsRune(safe, r)
	}) != -1 {
		return "'" + strings.ReplaceAll(value, "'", "'\\''") + "'"
	}
	return value
}

func freshnessValue(profile *FreshnessProfile, getter func(*FreshnessProfile) string) string {
	if profile == nil {
		return ""
	}
	return getter(profile)
}

func syncLatencyValue(profile *SyncLatencyProfile, getter func(*SyncLatencyProfile) string) string {
	if profile == nil {
		return ""
	}
	return getter(profile)
}

func workloadDriftValue(profile *WorkloadDriftProfile, getter func(*WorkloadDriftProfile) string) string {
	if profile == nil {
		return ""
	}
	return getter(profile)
}

func thermalValue(profile *ThermalProfile, getter func(*ThermalProfile) string) string {
	if profile == nil {
		return ""
	}
	return getter(profile)
}

func materializeThermalProfile(cfg scenario.ThermalConfig, derivedDir string) (*ThermalProfile, error) {
	if !cfg.Enabled {
		return nil, nil
	}
	observationStep := cfg.Ambient.ObservationStepS
	if observationStep <= 0 {
		observationStep = 5
	}
	horizon := cfg.Ambient.HorizonS
	if horizon <= 0 {
		horizon = 60
	}
	thermalTables := make([]ThermalTableProfile, 0, len(cfg.Tables))
	for _, table := range cfg.Tables {
		thermalTables = append(thermalTables, ThermalTableProfile{
			Name:               table.Name,
			Role:               table.Role,
			InitialTemperature: table.InitialTemperature,
			TargetTemperature:  table.TargetTemperature,
			HeatCapacity:       table.HeatCapacity,
			AccessWeight:       table.AccessWeight,
			IOWeight:           table.IOWeight,
			Coupling:           table.Coupling,
		})
	}
	traceLines := []string{"time_seconds,table,temperature,access_heat,io_heat,coupling_flux,error"}
	for _, table := range thermalTables {
		traceLines = append(traceLines, fmt.Sprintf("0,%s,%s,%s,%s,%s,0", table.Name, formatFloat(table.InitialTemperature), formatFloat(table.AccessWeight), formatFloat(table.IOWeight), formatFloat(table.Coupling)))
		traceLines = append(traceLines, fmt.Sprintf("%d,%s,%s,%s,%s,%s,0", horizon, table.Name, formatFloat(table.TargetTemperature), formatFloat(table.AccessWeight), formatFloat(table.IOWeight), formatFloat(table.Coupling)))
	}
	tracePath := filepath.Join(derivedDir, "thermal-temperature-trace.csv")
	if err := os.WriteFile(tracePath, []byte(strings.Join(traceLines, "\n")+"\n"), 0o644); err != nil {
		return nil, err
	}
	tableProfilePath := filepath.Join(derivedDir, "table-temperature-profile.json")
	if err := writeJSON(tableProfilePath, thermalTables); err != nil {
		return nil, err
	}
	return &ThermalProfile{
		Enabled:           true,
		Profile:           cfg.Profile,
		Model:             cfg.Model,
		PrimaryStateTable: cfg.PrimaryStateTable,
		AmbientBaseline:   cfg.Ambient.Baseline,
		CoolingRate:       cfg.Ambient.CoolingRate,
		ObservationStepS:  observationStep,
		HorizonS:          horizon,
		SteadyState:       cfg.Intent.SteadyState,
		TransientState:    cfg.Intent.TransientState,
		TargetTemperature: cfg.Intent.TargetTemperature,
		DriftRate:         cfg.Intent.DriftRate,
		HeatBudget:        cfg.Intent.HeatBudget,
		TableCount:        len(thermalTables),
		TracePath:         "derived/thermal-temperature-trace.csv",
		TableProfilePath:  "derived/table-temperature-profile.json",
		Tables:            thermalTables,
		Status:            "materialized",
	}, nil
}

func manifestStringOrEnv(manifest benchruntime.Manifest, key string, fallback string) string {
	if value := strings.TrimSpace(manifest.Get(key)); value != "" {
		return value
	}
	if value := strings.TrimSpace(os.Getenv(key)); value != "" {
		return value
	}
	return fallback
}

func manifestIntOrEnv(manifest benchruntime.Manifest, key string, fallback int) int {
	if value := strings.TrimSpace(manifest.Get(key)); value != "" {
		if parsed, err := strconv.Atoi(value); err == nil {
			return parsed
		}
	}
	if value := strings.TrimSpace(os.Getenv(key)); value != "" {
		if parsed, err := strconv.Atoi(value); err == nil {
			return parsed
		}
	}
	return fallback
}

func manifestFloatOrEnv(manifest benchruntime.Manifest, key string, fallback float64) float64 {
	if value := strings.TrimSpace(manifest.Get(key)); value != "" {
		if parsed, err := strconv.ParseFloat(value, 64); err == nil {
			return parsed
		}
	}
	if value := strings.TrimSpace(os.Getenv(key)); value != "" {
		if parsed, err := strconv.ParseFloat(value, 64); err == nil {
			return parsed
		}
	}
	return fallback
}

func manifestBoolOrEnv(manifest benchruntime.Manifest, key string, fallback bool) bool {
	if value := strings.TrimSpace(manifest.Get(key)); value != "" {
		return parseBool(value)
	}
	if value := strings.TrimSpace(os.Getenv(key)); value != "" {
		return parseBool(value)
	}
	return fallback
}

func parseBool(value string) bool {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "1", "true", "yes", "on":
		return true
	default:
		return false
	}
}

func formatFloat(value float64) string {
	return strconv.FormatFloat(value, 'f', -1, 64)
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}
