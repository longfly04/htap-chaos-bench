# Project-root config

This directory is the user-facing home for shared manifest defaults.

Source order for leaf manifests:
1. `config/project-paths.env`
2. `config/paper1-runtime.env`
3. `config/go-platform.env` for Go-backed runs
4. `config/job-hotspot.env` for hotspot-based JOB runs
5. `config/observability-snapshot.env` for snapshot-based runs
6. `config/chaos.env` for chaos-enabled runs
7. `config/workload-drift.env` for workload-drift runs

Supporting config files:
- `config/run-hooks.env` — local hook entry points used by manifests
- `config/site.env.example` — copy to `config/site.env` for machine-specific paths such as `SOURCE_PG_BINDIR`, `JOB_BENCHMARK_ROOT`, `SYSBENCH_BIN`, and observability extension roots

Runtime companion files:
- `pglab/compose/.env.example` — copy to `pglab/compose/.env` for the local container lab

Leaf manifests keep only scenario-specific overrides and `RUN_ID` / `RUN_NAME` / `SEED` identity fields.
