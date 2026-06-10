package scenario

type Scenario struct {
	System     string          `yaml:"system" json:"system"`
	Dataset    string          `yaml:"dataset" json:"dataset"`
	Snapshot   string          `yaml:"snapshot" json:"snapshot"`
	Budget     string          `yaml:"budget_tier" json:"budget_tier"`
	TP         TPConfig        `yaml:"tp" json:"tp"`
	AP         APConfig        `yaml:"ap" json:"ap"`
	HTAPCheck  HTAPCheckConfig `yaml:"htap_check" json:"htap_check"`
	Chaos      ChaosConfig     `yaml:"chaos" json:"chaos"`
	Drift      DriftConfig     `yaml:"drift" json:"drift"`
	Observe    ObserveConfig   `yaml:"observe" json:"observe"`
	Validation ValidateConfig  `yaml:"validate" json:"validate"`
	Seed       int             `yaml:"seed" json:"seed"`
}

type TPConfig struct {
	Profile     string      `yaml:"profile" json:"profile"`
	Driver      string      `yaml:"driver" json:"driver"`
	Concurrency int         `yaml:"concurrency" json:"concurrency"`
	Terminals   int         `yaml:"terminals" json:"terminals"`
	RateCap     int         `yaml:"rate_cap" json:"rate_cap"`
	Intensity   TPIntensity `yaml:"intensity" json:"intensity"`
	Skew        TPSkew      `yaml:"skew" json:"skew"`
	Burst       TPBurst     `yaml:"burst" json:"burst"`
}

type TPIntensity struct {
	BatchSize int `yaml:"batch_size" json:"batch_size"`
}

type TPSkew struct {
	Mode         string `yaml:"mode" json:"mode"`
	HotModulus   int    `yaml:"hot_modulus" json:"hot_modulus"`
	HotRemainder int    `yaml:"hot_remainder" json:"hot_remainder"`
}

type TPBurst struct {
	Mode string `yaml:"mode" json:"mode"`
}

type APConfig struct {
	Class                string `yaml:"class" json:"class"`
	Arrival              string `yaml:"arrival" json:"arrival"`
	Terminals            int    `yaml:"terminals" json:"terminals"`
	Parallelism          int    `yaml:"parallelism" json:"parallelism"`
	BurstIntervalSeconds int    `yaml:"burst_interval_seconds" json:"burst_interval_seconds"`
}

type HTAPCheckConfig struct {
	Enabled bool   `yaml:"enabled" json:"enabled"`
	Type    string `yaml:"type" json:"type"`
}

type ChaosConfig struct {
	Mode              string           `yaml:"mode" json:"mode"`
	Stage             string           `yaml:"stage" json:"stage"`
	SafetyLevel       string           `yaml:"safety_level" json:"safety_level"`
	CleanupProfile    string           `yaml:"cleanup_profile" json:"cleanup_profile"`
	StartAfterSeconds int              `yaml:"start_after_seconds" json:"start_after_seconds"`
	DurationSeconds   int              `yaml:"duration_seconds" json:"duration_seconds"`
	Seed              int              `yaml:"seed" json:"seed"`
	Injections        []ChaosInjection `yaml:"injections" json:"injections"`
}

type ChaosInjection struct {
	ID             string      `yaml:"id" json:"id"`
	Family         string      `yaml:"family" json:"family"`
	Primitive      string      `yaml:"primitive" json:"primitive"`
	TargetSelector string      `yaml:"target_selector" json:"target_selector"`
	Intensity      string      `yaml:"intensity" json:"intensity"`
	Params         ChaosParams `yaml:"params" json:"params"`
}

type ChaosParams struct {
	Jobs            int     `yaml:"jobs" json:"jobs"`
	LockHoldSeconds int     `yaml:"lock_hold_seconds" json:"lock_hold_seconds"`
	Fixture         bool    `yaml:"fixture" json:"fixture"`
	Workers         int     `yaml:"workers" json:"workers"`
	SessionMemory   string  `yaml:"session_memory" json:"session_memory"`
	Rate            float64 `yaml:"rate" json:"rate"`
}

type DriftConfig struct {
	DataFactor     float64  `yaml:"data_factor" json:"data_factor"`
	WorkloadFactor float64  `yaml:"workload_factor" json:"workload_factor"`
	FeatureScope   []string `yaml:"feature_scope" json:"feature_scope"`
}

type ObserveConfig struct {
	ExportPGStats          bool   `yaml:"export_pg_stats" json:"export_pg_stats"`
	SamplingIntervalSeconds int    `yaml:"sampling_interval_seconds" json:"sampling_interval_seconds"`
	MetricsProfile          string `yaml:"metrics_profile" json:"metrics_profile"`
	RenderPlots             bool   `yaml:"render_plots" json:"render_plots"`
	PlotProfile             string `yaml:"plot_profile" json:"plot_profile"`
	PlotDPI                 int    `yaml:"plot_dpi" json:"plot_dpi"`
	CompareGroup            string `yaml:"compare_group" json:"compare_group"`
}

type ValidateConfig struct {
	Consistency bool `yaml:"consistency" json:"consistency"`
	Recovery    bool `yaml:"recovery" json:"recovery"`
}
