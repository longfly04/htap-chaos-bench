package tpgen

import (
	"fmt"
	"math"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	driftpkg "htap-chaos-bench/internal/drift"
	"gopkg.in/yaml.v3"
	"htap-chaos-bench/internal/dataset"
)

var (
	queryFeatureTablePattern     = regexp.MustCompile(`(?i)\b(?:from|join)\s+([a-zA-Z_][\w\.]*)`)
	queryFeatureJoinPattern      = regexp.MustCompile(`(?i)\bjoin\b`)
	queryFeatureWherePattern     = regexp.MustCompile(`(?is)\bwhere\b(.*?)(?:\bgroup\s+by\b|\border\s+by\b|\blimit\b|;)`)
	queryFeaturePredicatePattern = regexp.MustCompile(`(?i)\s+\b(?:and|or)\b\s+`)
	queryFeatureWhitespace       = regexp.MustCompile(`\s+`)
)

type WorkloadDriftProfile struct {
	Enabled                bool     `json:"enabled"`
	DataFactor             float64  `json:"data_factor"`
	WorkloadFactor         float64  `json:"workload_factor"`
	RealizedWorkloadFactor float64  `json:"realized_workload_factor"`
	BaseQueryClass         string   `json:"base_query_class"`
	QueryCorpusSize        int      `json:"query_corpus_size"`
	SampleSize             int      `json:"sample_size"`
	FeatureScope           []string `json:"feature_scope"`
	APClassesSource        string   `json:"ap_classes_source"`
	QueryFeatureBinsSource string   `json:"query_feature_bins_source,omitempty"`
	QueryFeatureMapPath    string   `json:"query_feature_map_path"`
	BeforeDistributionPath string   `json:"before_distribution_path"`
	AfterDistributionPath  string   `json:"after_distribution_path"`
	DriftSamplePath        string   `json:"drift_sample_path"`
	BeforeQueryIDs         []string `json:"before_query_ids"`
	AfterQueryIDs          []string `json:"after_query_ids"`
	Status                 string   `json:"status"`
}

type QueryFeature struct {
	ID             string   `json:"id"`
	QueryClass     string   `json:"query_class"`
	QueryPath      string   `json:"query_path"`
	Tables         []string `json:"tables"`
	TableCount     int      `json:"table_count"`
	JoinCount      int      `json:"join_count"`
	Predicates     []string `json:"predicates"`
	PredicateCount int      `json:"predicate_count"`
	SQLText        string   `json:"-"`
}

type QueryFeatureDistribution struct {
	QueryCount          int                `json:"query_count"`
	QueryClass          map[string]float64 `json:"query_class"`
	TableCount          map[string]float64 `json:"table_count"`
	JoinCount           map[string]float64 `json:"join_count"`
	PredicateCount      map[string]float64 `json:"predicate_count"`
	Tables              map[string]float64 `json:"tables"`
	Predicates          map[string]float64 `json:"predicates"`
	AliasNameFullName   map[string]float64 `json:"aliasname_fullname,omitempty"`
	SelectedQueryIDs    []string           `json:"selected_query_ids"`
}

type queryClassMap map[string][]string

func materializeWorkloadDrift(datasetRoot string, pack dataset.Pack, derivedDir string, baseQueryClass string, featureScope []string, dataFactor, workloadFactor float64, sampleSize, seed int) (*WorkloadDriftProfile, error) {
	if workloadFactor <= 0 {
		return nil, nil
	}
	classesSource := strings.TrimSpace(firstNonEmpty(pack.APClassesFile, "queries/classes.yaml"))
	classesPath := filepath.Join(datasetRoot, filepath.FromSlash(classesSource))
	classes, err := loadQueryClasses(classesPath)
	if err != nil {
		return nil, err
	}
	features, err := loadQueryFeatures(datasetRoot, classes)
	if err != nil {
		return nil, err
	}
	if len(features) == 0 {
		return nil, fmt.Errorf("no AP queries found for workload drift in %s", classesSource)
	}
	baseQueries := featuresForClass(features, baseQueryClass)
	if len(baseQueries) == 0 {
		return nil, fmt.Errorf("no AP queries found for workload drift base class %s", baseQueryClass)
	}
	if sampleSize <= 0 {
		sampleSize = 6
	}
	featureScope = driftpkg.NormalizeFeatureScope(featureScope)
	beforeSample := repeatQueryFeatures(baseQueries, sampleSize, seed)
	afterSample := buildDriftSample(beforeSample, featuresExcludingClass(features, baseQueryClass), workloadFactor, seed)
	beforeDist := buildQueryFeatureDistribution(beforeSample)
	afterDist := buildQueryFeatureDistribution(afterSample)
	realizedFactor := roundMetric(computeWorkloadDriftFactor(beforeDist, afterDist, featureScope))

	queryFeatureMapPath := filepath.Join(derivedDir, "query-feature-map.json")
	beforeDistPath := filepath.Join(derivedDir, "query-feature-dist.before.json")
	afterDistPath := filepath.Join(derivedDir, "query-feature-dist.after.json")
	driftSamplePath := filepath.Join(derivedDir, "query-drift-sample.sql")
	factorPath := filepath.Join(derivedDir, "workload-drift-factor.json")

	if err := writeJSON(queryFeatureMapPath, map[string]any{
		"ap_classes_source":         classesSource,
		"query_feature_bins_source": strings.TrimSpace(pack.QueryFeatureBins),
		"base_query_class":          baseQueryClass,
		"query_count":               len(features),
		"queries":                   features,
	}); err != nil {
		return nil, err
	}
	if err := writeJSON(beforeDistPath, beforeDist); err != nil {
		return nil, err
	}
	if err := writeJSON(afterDistPath, afterDist); err != nil {
		return nil, err
	}
	if err := os.WriteFile(driftSamplePath, []byte(buildDriftSampleSQL(afterSample)), 0o644); err != nil {
		return nil, err
	}

	profile := &WorkloadDriftProfile{
		Enabled:                true,
		DataFactor:             dataFactor,
		WorkloadFactor:         roundMetric(workloadFactor),
		RealizedWorkloadFactor: realizedFactor,
		BaseQueryClass:         baseQueryClass,
		QueryCorpusSize:        len(features),
		SampleSize:             len(afterSample),
		FeatureScope:           featureScope,
		APClassesSource:        classesSource,
		QueryFeatureBinsSource: strings.TrimSpace(pack.QueryFeatureBins),
		QueryFeatureMapPath:    "derived/query-feature-map.json",
		BeforeDistributionPath: "derived/query-feature-dist.before.json",
		AfterDistributionPath:  "derived/query-feature-dist.after.json",
		DriftSamplePath:        "derived/query-drift-sample.sql",
		BeforeQueryIDs:         beforeDist.SelectedQueryIDs,
		AfterQueryIDs:          afterDist.SelectedQueryIDs,
		Status:                 "materialized",
	}
	if err := writeJSON(factorPath, profile); err != nil {
		return nil, err
	}
	return profile, nil
}

func loadQueryClasses(path string) (queryClassMap, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var classes queryClassMap
	if err := yaml.Unmarshal(data, &classes); err != nil {
		return nil, err
	}
	return classes, nil
}

func loadQueryFeatures(datasetRoot string, classes queryClassMap) ([]QueryFeature, error) {
	classNames := make([]string, 0, len(classes))
	for className := range classes {
		classNames = append(classNames, className)
	}
	sort.Strings(classNames)
	features := make([]QueryFeature, 0)
	for _, className := range classNames {
		paths := append([]string(nil), classes[className]...)
		sort.Strings(paths)
		for _, relativePath := range paths {
			fullPath := filepath.Join(datasetRoot, filepath.FromSlash(relativePath))
			data, err := os.ReadFile(fullPath)
			if err != nil {
				return nil, err
			}
			sqlText := string(data)
			tables := extractTables(sqlText)
			predicates := extractPredicates(sqlText)
			normalizedPath := filepath.ToSlash(relativePath)
			id := strings.TrimSuffix(normalizedPath, filepath.Ext(normalizedPath))
			features = append(features, QueryFeature{
				ID:             id,
				QueryClass:     className,
				QueryPath:      normalizedPath,
				Tables:         tables,
				TableCount:     len(tables),
				JoinCount:      len(queryFeatureJoinPattern.FindAllString(sqlText, -1)),
				Predicates:     predicates,
				PredicateCount: len(predicates),
				SQLText:        sqlText,
			})
		}
	}
	return features, nil
}

func featuresForClass(features []QueryFeature, className string) []QueryFeature {
	selected := make([]QueryFeature, 0)
	for _, feature := range features {
		if feature.QueryClass == className {
			selected = append(selected, feature)
		}
	}
	return selected
}

func featuresExcludingClass(features []QueryFeature, className string) []QueryFeature {
	selected := make([]QueryFeature, 0)
	for _, feature := range features {
		if feature.QueryClass != className {
			selected = append(selected, feature)
		}
	}
	return selected
}

func repeatQueryFeatures(pool []QueryFeature, count, seed int) []QueryFeature {
	if len(pool) == 0 || count <= 0 {
		return nil
	}
	start := normalizedIndex(seed, len(pool))
	sample := make([]QueryFeature, 0, count)
	for index := 0; index < count; index++ {
		sample = append(sample, pool[(start+index)%len(pool)])
	}
	return sample
}

func buildDriftSample(baseSample, alternateQueries []QueryFeature, workloadFactor float64, seed int) []QueryFeature {
	if len(baseSample) == 0 {
		return nil
	}
	afterSample := append([]QueryFeature(nil), baseSample...)
	if workloadFactor <= 0 || len(alternateQueries) == 0 {
		return afterSample
	}
	driftCount := int(math.Round(workloadFactor * float64(len(baseSample))))
	if driftCount <= 0 {
		driftCount = 1
	}
	if driftCount >= len(baseSample) {
		driftCount = len(baseSample) - 1
	}
	if driftCount <= 0 {
		return afterSample
	}
	baseCount := len(baseSample) - driftCount
	drifted := make([]QueryFeature, 0, len(baseSample))
	drifted = append(drifted, afterSample[:baseCount]...)
	drifted = append(drifted, repeatQueryFeatures(alternateQueries, driftCount, seed+len(baseSample)+1)...)
	return drifted
}

func buildQueryFeatureDistribution(sample []QueryFeature) QueryFeatureDistribution {
	queryClassCounts := map[string]int{}
	tableCountCounts := map[string]int{}
	joinCountCounts := map[string]int{}
	predicateCountCounts := map[string]int{}
	tableTokenCounts := map[string]int{}
	predicateTokenCounts := map[string]int{}
	selectedQueryIDs := make([]string, 0, len(sample))

	for _, feature := range sample {
		selectedQueryIDs = append(selectedQueryIDs, feature.ID)
		queryClassCounts[feature.QueryClass]++
		tableCountCounts[fmt.Sprintf("%d", feature.TableCount)]++
		joinCountCounts[fmt.Sprintf("%d", feature.JoinCount)]++
		predicateCountCounts[fmt.Sprintf("%d", feature.PredicateCount)]++
		for _, table := range feature.Tables {
			tableTokenCounts[table]++
		}
		for _, predicate := range feature.Predicates {
			predicateTokenCounts[predicate]++
		}
	}

	return QueryFeatureDistribution{
		QueryCount:       len(sample),
		QueryClass:       normalizeCountMap(queryClassCounts),
		TableCount:       normalizeCountMap(tableCountCounts),
		JoinCount:        normalizeCountMap(joinCountCounts),
		PredicateCount:   normalizeCountMap(predicateCountCounts),
		Tables:             normalizeCountMap(tableTokenCounts),
		Predicates:         normalizeCountMap(predicateTokenCounts),
		AliasNameFullName:   normalizeCountMap(tableTokenCounts),
		SelectedQueryIDs:    selectedQueryIDs,
	}
}

func buildDriftSampleSQL(sample []QueryFeature) string {
	var builder strings.Builder
	for index, feature := range sample {
		builder.WriteString(fmt.Sprintf("-- workload drift sample %02d: %s (%s)\n", index+1, feature.ID, feature.QueryClass))
		statement := strings.TrimSpace(feature.SQLText)
		builder.WriteString(statement)
		if !strings.HasSuffix(statement, ";") {
			builder.WriteString(";")
		}
		builder.WriteString("\n\n")
	}
	return builder.String()
}

func extractTables(sqlText string) []string {
	seen := map[string]struct{}{}
	tables := make([]string, 0)
	for _, match := range queryFeatureTablePattern.FindAllStringSubmatch(sqlText, -1) {
		if len(match) < 2 {
			continue
		}
		table := normalizeTableName(match[1])
		if table == "" {
			continue
		}
		if _, ok := seen[table]; ok {
			continue
		}
		seen[table] = struct{}{}
		tables = append(tables, table)
	}
	return tables
}

func extractPredicates(sqlText string) []string {
	match := queryFeatureWherePattern.FindStringSubmatch(sqlText)
	if len(match) < 2 {
		return nil
	}
	parts := queryFeaturePredicatePattern.Split(match[1], -1)
	predicates := make([]string, 0, len(parts))
	for _, part := range parts {
		normalized := strings.TrimSpace(queryFeatureWhitespace.ReplaceAllString(part, " "))
		normalized = strings.TrimSuffix(normalized, ";")
		if normalized == "" {
			continue
		}
		predicates = append(predicates, normalized)
	}
	return predicates
}

func normalizeTableName(name string) string {
	trimmed := strings.TrimSpace(name)
	trimmed = strings.Trim(trimmed, `"`)
	parts := strings.Split(trimmed, ".")
	return strings.Trim(parts[len(parts)-1], `"`)
}

func normalizeCountMap(counts map[string]int) map[string]float64 {
	result := make(map[string]float64, len(counts))
	total := 0
	for _, count := range counts {
		total += count
	}
	if total <= 0 {
		return result
	}
	for key, count := range counts {
		result[key] = roundMetric(float64(count) / float64(total))
	}
	return result
}

func computeWorkloadDriftFactor(before, after QueryFeatureDistribution, featureScope []string) float64 {
	divergences := make([]float64, 0, len(featureScope))
	for _, feature := range featureScope {
		switch feature {
		case "query_class":
			divergences = append(divergences, jsDivergence(before.QueryClass, after.QueryClass))
		case "table_count":
			divergences = append(divergences, jsDivergence(before.TableCount, after.TableCount))
		case "join_count":
			divergences = append(divergences, jsDivergence(before.JoinCount, after.JoinCount))
		case "predicate_count":
			divergences = append(divergences, jsDivergence(before.PredicateCount, after.PredicateCount))
		case "aliasname_fullname":
				divergences = append(divergences, jsDivergence(before.AliasNameFullName, after.AliasNameFullName))
			case "tables":
			divergences = append(divergences, jsDivergence(before.Tables, after.Tables))
		case "predicates":
			divergences = append(divergences, jsDivergence(before.Predicates, after.Predicates))
		}
	}
	if len(divergences) == 0 {
		return 0
	}
	total := 0.0
	for _, divergence := range divergences {
		total += divergence
	}
	return total / float64(len(divergences))
}

func jsDivergence(left, right map[string]float64) float64 {
	keys := make([]string, 0, len(left)+len(right))
	seen := map[string]struct{}{}
	for key := range left {
		if _, ok := seen[key]; !ok {
			seen[key] = struct{}{}
			keys = append(keys, key)
		}
	}
	for key := range right {
		if _, ok := seen[key]; !ok {
			seen[key] = struct{}{}
			keys = append(keys, key)
		}
	}
	if len(keys) == 0 {
		return 0
	}
	divergence := 0.0
	for _, key := range keys {
		p := left[key]
		q := right[key]
		m := 0.5 * (p + q)
		if p > 0 {
			divergence += 0.5 * p * math.Log2(p/m)
		}
		if q > 0 {
			divergence += 0.5 * q * math.Log2(q/m)
		}
	}
	return roundMetric(divergence)
}

func roundMetric(value float64) float64 {
	return math.Round(value*1_000_000) / 1_000_000
}

func normalizedIndex(seed, length int) int {
	if length <= 0 {
		return 0
	}
	if seed < 0 {
		seed = -seed
	}
	return seed % length
}
