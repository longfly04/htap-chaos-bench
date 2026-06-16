# paper1 executable experiment matrix

## Global dimensions

| Dimension | Values | Notes |
|---|---|---|
| System | pg-like | 第一波只做 PostgreSQL-like 单系统闭环。 |
| Dataset | job / job-small | 先用 JOB，允许 smoke 使用缩小版 snapshot。 |
| Memory budget tier | generous / moderate / tight | 先由 AP-only spill / plan cliff 标定。 |
| TP pressure | low / medium / high | 先由 TP-only saturation curve 标定。 |
| AP class | sort-heavy / hash-heavy / mixed | 先从 `sort-heavy` 开始。 |
| Overlap semantics | tp-first / ap-first / repeated-burst | Phase 1 以前两类为主。 |
| Seed count | 1 for smoke, 5 per stable point | smoke 先单 seed，正式切片再扩 5 seeds。 |
| Cache mode | warm / cold / churned | 同组对照不能混用。 |

## Run naming convention

`<rq>_<system>_<budget>_<tp>_<overlap>_<ap>_<variant>_s<seed>`

Examples:
- `SMOKE_pg-like_moderate_low_tp-first_mixed_smoke_s1`
- `P1TP_pg-like_moderate_medium_tp-first_na_native_s1`
- `P1AP_pg-like_tight_low_tp-first_sort-heavy_native_s1`
- `P1LOCK_pg-like_moderate_medium_tp-first_mixed_waitxact_s1`

## Phase 0.5 slices

| Slice ID | Goal | Manifest |
|---|---|---|
| SMOKE-A | shared dry-run | `manifests/smoke/job-pg-smoke.env` |
| SMOKE-B | pg-like runtime + P0 validation | `manifests/smoke/job-pg-smoke.env` |

## Phase 1 slices

| Slice ID | Goal | Manifest family |
|---|---|---|
| P1-TP | TP-only saturation low/medium/high | `manifests/phase1/tp-only-*.env` |
| P1-AP | AP-only spill / plan cliff | `manifests/phase1/ap-only-*.env` |
| P1-LOCK | lock / wait baseline | `manifests/phase1/lock-wait-baseline.env` |

## Phase 2 slices

| Slice ID | Goal | Manifest |
|---|---|---|
| P2-STATS | stats export smoke | `manifests/phase2/generator-smoke.env` |
| P2-GEN | schema graph + template smoke | `manifests/phase2/generator-smoke.env` |
| P2-DRIFT | update/drift smoke | `manifests/phase2/generator-smoke.env` |

## Phase 3 slices

| Slice ID | Goal | Manifest |
|---|---|---|
| P3-WAIT | mixed TP+AP + `wait_xact` single-fault L1 + recovery window | `manifests/phase3/go-mixed-waitxact-l1.env` |
| P3-DEADLOCK | mixed TP+AP + `deadlock_pair` single-fault L1 + deadlock error / cleanup evidence | `manifests/phase3/go-mixed-deadlock-l1.env` |
| P3-SPILL | mixed TP+AP + `spill_pressure` single-fault L1 + temp-bytes / cleanup evidence | `manifests/phase3/go-mixed-spill-l1.env` |

## Phase 4 slices

| Slice ID | Goal | Manifest |
|---|---|---|
| P4-FRESH | mixed TP+AP + `query-oriented freshness` probe + `freshness-check.json` / `htapcheck/freshness.csv` evidence | `manifests/phase4/go-mixed-query-freshness.env` |
| P4-SYNC | mixed TP+AP + `sync-latency` probe + `sync-latency.json` / `htapcheck/sync-latency.csv` evidence | `manifests/phase4/go-mixed-sync-latency.env` |
| P4-DRIFT | mixed TP+AP + `workload drift` sample + `workload-drift-factor.json` / `query-feature-dist.before.json` / `query-feature-dist.after.json` evidence | `manifests/phase4/go-mixed-workload-drift.env` |

## Phase 5 evidence closure

> 说明：这一阶段先以 pg-like / JOB 为主，把 multiple seeds、cross-system pilot 和 head-to-head baseline 做成可复用的证据矩阵；尚未具备 adapter 的系统一律标为 `adapter-limited`。

| Slice ID | Goal | Manifest |
|---|---|---|
| P5-SEEDS | 对稳定点做 multiple seeds（默认 5） 的重复运行，产出 mean / std / boxplot 输入 | `manifests/phase5/seed-sweep-workload-drift.env` |
| P5-XSYS | 在同一逻辑压力下做 cross-system pilot，对 adapter-limited 系统显式标注 | `manifests/phase5/cross-system-workload-drift.env` |
| P5-H2H | 对当前 Go-backed path 与旧固定脚本 / 既有 baseline 做 head-to-head 对照 | `manifests/phase5/head-to-head-workload-drift-go.env` + `manifests/phase5/head-to-head-workload-drift-legacy.env` |
| P5-MFAULT | 在 mixed steady-state 中组合 wait_xact / spill_pressure / deadlock_pair，验证多故障编排与恢复闭环 | `manifests/phase5/go-mixed-multifault-mainline.env` |
| P5-DRIFT+ | 提高 workload drift 强度并叠加 sync-latency 观测，产出更有信息量的 drift/HTAP 证据 | `manifests/phase5/go-mixed-workload-drift-heavy.env` |
