# htap-chaos-bench

Standalone benchmark project for the mixed-load chaos benchmarking stack.

## Boundary
- Canonical source: this project
- Local harness: `scripts/` now vendors the run-slice / runtime-launch / PostgreSQL helper scripts required by this project
- Local lab: `pglab/` now carries the project-owned PostgreSQL container lab instead of borrowing `paper3-memory-scheduling/pglab`
- Paper consumers: `Papers/paper1-memhtap-benchmark/`
- local harness scripts live inside this project; no runtime script dependency remains on `Papers/_shared/`

## Layout
- `go.mod`, `cmd/`, `internal/`, `scripts/` — Go control plane
- `config/` — user-facing shared env defaults, site template overlays, and manifest layering entry point
- `pglab/` — project-local PostgreSQL lab assets and compose template
- `exp/` — manifests, scenarios, datasets, run scripts, validation, SQL
- `exp/results/` — runtime output area, not paper1 manuscript evidence

## Remote setup
- Copy `config/site.env.example` to `config/site.env` and fill in host-specific values such as `SOURCE_PG_BINDIR` and `JOB_BENCHMARK_ROOT`.
- Copy `pglab/compose/.env.example` to `pglab/compose/.env` before container-mode runs.
- Run commands from the project root so `scripts/run_slice.sh` keeps `LAB_ROOT=$PWD` and automatically resolves the local `pglab/` bundle.
