# Local pglab

This directory contains the project-local PostgreSQL lab used by `scripts/run_slice.sh` and `scripts/harness_start.sh`.

## Setup
- Copy `compose/.env.example` to `compose/.env` for ad hoc local runs, or point `LAB_ENV_FILE` directly at one of the tracked profile env files under `compose/profiles/`.
- Copy `../config/site.env.example` to `../config/site.env` if you need source-runtime binaries or real JOB reload inputs.
- Run benchmark commands from the project root so `LAB_ROOT=$PWD` and the harness resolves this local `pglab/` automatically.

## Container profiles and extension image
- Tracked container profiles live at:
  - `compose/profiles/4u4g.env`
  - `compose/profiles/4u8g.env`
  - `compose/profiles/8u8g.env`
  - `compose/profiles/8u16g.env`
- Each profile binds together:
  - cgroup resource limits (`CGROUP_CPU_LIMIT`, `CGROUP_MEMORY_LIMIT`, `CGROUP_MEMORY_RESERVATION`)
  - the pgtune-derived PostgreSQL parameters documented below
  - a dedicated `COMPOSE_PROJECT_NAME`, `DB_PORT`, and `MEMORY_PROFILE`
  - the required observability contract (`OBSERVE_REQUIRED_EXTENSIONS`, `OBSERVE_REQUIRED_PRELOAD_LIBRARIES`, `OBSERVE_REQUIRED_COMMANDS`)
  - high-pressure TP/AP defaults (`JOB_WARMUP_SECONDS`, `JOB_DURATION_SECONDS`, `JOB_MEASURE_SECONDS`, `JOB_TP_THREADS_*`, `JOB_TP_TERMINALS`, `JOB_AP_TERMINALS`, `JOB_AP_PARALLELISM`)
- `compose/docker-compose.yml` builds a custom PostgreSQL image via `docker/Dockerfile.pgext`.
- The intended remote build context is `/home/sducs/postgresql-dev`, so the image can compile extension sources and install `pg_activity` from `/home/sducs/postgresql-dev/extensions` without syncing those sources into this project.
- The custom image installs:
  - `pg_wait_sampling`
  - `pgmeminfo`
  - `system_stats`
  - `pg_stat_kcache`
  - `pg_activity`
- The container runtime preloads:
  - `pg_stat_statements`
  - `pg_wait_sampling`
  - `pg_stat_kcache`
- Runtime preflight also requires `pg_activity` to be callable inside the container, and mixed runs now emit best-effort `pg_activity` CSV snapshots under `observability/timeline/pg-activity/` plus an end-of-run `observability/pg_activity.final.csv` snapshot.

## Batch execution flow
- `scripts/run_profile_matrix.sh <4u4g|4u8g|8u8g|8u16g>` is the top-level entrypoint for a full profile run.
- It performs:
  1. image build
  2. container startup
  3. extension / preload / runtime-command preflight via `exp/scripts/prepare/00_env_sanity.sh`
  4. tier0 → tier3 batch execution
- The per-tier scripts (`scripts/run_tier*_batch.sh`) also accept an optional profile argument and reuse `scripts/batch_profile_common.sh` to bind the right profile env, run root, and batch log directory.
- Per-run metadata snapshots include the resolved profile env and profile identifiers so later aggregation can preserve hardware-profile boundaries across the 4-profile matrix.

## Path contract
- The project root is mounted into the container as `/workspace/htap-chaos-bench`.
- The run root is mounted as `/workspace/runs`.
- Project SQL continues to resolve through `/workspace/htap-chaos-bench/exp/sql/...`.

## Scope
This is a minimal postgres-only lab adapted for `htap-chaos-bench`. It intentionally does not depend on paper3's BudgetFlow Dockerfiles or benchmark runner services.

## PGTune参数

### 4U4G

```config
# WARNING
# wal_compression = lz4 requires PostgreSQL
# to be compiled with --with-lz4

# DB Version: 17
# OS Type: linux
# DB Type: mixed
# Total Memory (RAM): 4 GB
# CPUs num: 4
# Connections num: 500
# Data Storage: hdd

max_connections = 500
shared_buffers = 1GB
effective_cache_size = 3GB
maintenance_work_mem = 256MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 4
effective_io_concurrency = 2
work_mem = 4MB
huge_pages = try
jit = off
wal_compression = lz4
autovacuum_max_workers = 4
min_wal_size = 1GB
max_wal_size = 4GB
max_worker_processes = 4
max_parallel_workers_per_gather = 2
max_parallel_workers = 4
max_parallel_maintenance_workers = 2
temp_file_limit = -1
```

### 4U8G

```config
# WARNING
# wal_compression = lz4 requires PostgreSQL
# to be compiled with --with-lz4

# DB Version: 17
# OS Type: linux
# DB Type: mixed
# Total Memory (RAM): 8 GB
# CPUs num: 4
# Connections num: 500
# Data Storage: hdd

max_connections = 500
shared_buffers = 2GB
effective_cache_size = 6GB
maintenance_work_mem = 512MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 4
effective_io_concurrency = 2
work_mem = 4MB
huge_pages = try
jit = off
wal_compression = lz4
autovacuum_max_workers = 4
min_wal_size = 1GB
max_wal_size = 4GB
max_worker_processes = 4
max_parallel_workers_per_gather = 2
max_parallel_workers = 4
max_parallel_maintenance_workers = 2
temp_file_limit = -1
```

### 8U8G

```config
# WARNING
# wal_compression = lz4 requires PostgreSQL
# to be compiled with --with-lz4

# DB Version: 17
# OS Type: linux
# DB Type: mixed
# Total Memory (RAM): 8 GB
# CPUs num: 8
# Connections num: 500
# Data Storage: hdd

max_connections = 500
shared_buffers = 2GB
effective_cache_size = 6GB
maintenance_work_mem = 512MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 4
effective_io_concurrency = 2
work_mem = 4MB
huge_pages = try
jit = off
wal_compression = lz4
autovacuum_max_workers = 4
min_wal_size = 1GB
max_wal_size = 4GB
max_worker_processes = 8
max_parallel_workers_per_gather = 4
max_parallel_workers = 8
max_parallel_maintenance_workers = 4
temp_file_limit = -1
```

### 8U16G

```config
# WARNING
# wal_compression = lz4 requires PostgreSQL
# to be compiled with --with-lz4

# DB Version: 17
# OS Type: linux
# DB Type: mixed
# Total Memory (RAM): 16 GB
# CPUs num: 8
# Connections num: 500
# Data Storage: hdd

max_connections = 500
shared_buffers = 4GB
effective_cache_size = 12GB
maintenance_work_mem = 1GB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 4
effective_io_concurrency = 2
work_mem = 4MB
huge_pages = try
jit = off
wal_compression = lz4
autovacuum_max_workers = 4
min_wal_size = 1GB
max_wal_size = 4GB
max_worker_processes = 8
max_parallel_workers_per_gather = 4
max_parallel_workers = 8
max_parallel_maintenance_workers = 4
temp_file_limit = -1
```