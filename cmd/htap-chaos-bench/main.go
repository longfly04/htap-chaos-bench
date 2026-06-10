package main

import (
	"flag"
	"fmt"
	"os"

	"htap-chaos-bench/internal/dataset"
	benchruntime "htap-chaos-bench/internal/runtime"
	"htap-chaos-bench/internal/scenario"
	"htap-chaos-bench/internal/tpgen"
)

func main() {
	if len(os.Args) < 2 {
		fatalf("usage: htap-chaos-bench <command> [args]")
	}

	switch os.Args[1] {
	case "materialize-tp":
		materializeTP(os.Args[2:])
	default:
		fatalf("unknown command: %s", os.Args[1])
	}
}

func materializeTP(args []string) {
	fs := flag.NewFlagSet("materialize-tp", flag.ExitOnError)
	manifestPath := fs.String("manifest", "", "manifest env path")
	scenarioPath := fs.String("scenario", "", "scenario yaml path")
	datasetPath := fs.String("dataset-pack", "", "dataset pack root")
	runDir := fs.String("run-dir", "", "run directory")
	_ = fs.Parse(args)

	if *manifestPath == "" || *scenarioPath == "" || *datasetPath == "" || *runDir == "" {
		fatalf("materialize-tp requires --manifest, --scenario, --dataset-pack, and --run-dir")
	}

	manifest, err := benchruntime.LoadManifest(*manifestPath)
	if err != nil {
		fatalErr(err)
	}
	scenarioSpec, err := scenario.LoadScenario(*scenarioPath)
	if err != nil {
		fatalErr(err)
	}
	datasetPack, err := dataset.LoadPack(*datasetPath)
	if err != nil {
		fatalErr(err)
	}

	if err := tpgen.MaterializeTP(tpgen.MaterializeRequest{
		Manifest:    manifest,
		Scenario:    scenarioSpec,
		DatasetPack: datasetPack,
		DatasetRoot: *datasetPath,
		RunDir:      *runDir,
	}); err != nil {
		fatalErr(err)
	}
}

func fatalErr(err error) {
	fatalf("%v", err)
}

func fatalf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", args...)
	os.Exit(1)
}
