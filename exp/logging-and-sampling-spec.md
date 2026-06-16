# paper1 logging and sampling spec

## 每个 run 至少保存
- `manifest.env`
- `manifest.resolved.txt`
- `stdout.log` / `stderr.log`
- `summary.json`
- `runtime/runtime.env`
- `compose/` 与 `configs/` 快照
- `observability/pg_settings.csv`
- `observability/pg_stat_database.csv`
- `observability/pg_stat_activity.csv`
- `observability/pg_locks.csv`

## lock-path slices 追加保存
- `observability/lock-snapshot.csv`
- `observability/blocking-tree.txt`
- `validation/recovery-check.json`

## 建议补充
- `observability/timeline/system-metrics.csv`
- `observability/timeline/activity-metrics.csv`
- `observability/timeline/statement-metrics.csv`
- `observability/timeline/io-metrics.csv`（若 `pg_stat_io` 可用）
- `observability/timeline/wait-metrics.csv`（若 `pg_wait_sampling` 可用）
- `observability/timeline/kcache-metrics.csv`（若 `pg_stat_kcache` 可用，记录 kernel/statement 级 CPU、read/write、context-switch 累积量）
- `observability/timeline/memory-metrics.csv`（buffer cache 为真实观测；若 `system_stats` 可用则 session/backend memory 为全局 backend 观测，否则回退到 sampler backend 粒度）
- `observability/system_stats_memory.csv`（若 `system_stats` 可用）
- `observability/system_stats_backend_memory.csv`（若 `system_stats` 可用）
- `observability/pg_stat_kcache.csv`（若 `pg_stat_kcache` 可用）
- `observability/timeline/ap-events.jsonl`
- `observability/timeline/capabilities.json`
- `observability/timeline/plot-metadata.json`
- `validation/plot-status.json`
- `tp/progress.csv`（driver-agnostic TP progress timeline）
- `tp/summary.json`（driver-agnostic TP aggregate metrics）
- `figures/run-overview.png` / `.pdf`
- `figures/run-panels.png` / `.pdf`
- `figures/plot-manifest.json`

## 原则
1. 所有 baseline 共用同一套时间轴和采样字段。
2. 优先采 engine-visible / SQL-visible 信号。
3. trace 图和 aggregate 表必须回到同一批 artifact。
4. 没有 validation bundle 的切片不得进入主文图表。

## 4. 六类主负载的监测与可视化映射
- `wait_xact`：优先看 lock wait 时间线、blocking tree、blocked sessions、top blocker age，以及恢复窗口中的 TP jitter。
- `spill_pressure/tempfiles`：优先看 temp bytes / temp files 的前后差值、AP latency 曲线、spill count、计划变化前后对比。
- `deadlock_pair`：优先看 deadlock 发生时间点、abort 数、锁树形状、session 日志与恢复耗时。
- `query-oriented freshness`：优先看 freshness gap、max epoch delta、pre/overlap/post 三段样本，以及 query-oriented probe 的结果 CSV。
- `sync-latency`：优先看 visibility latency、poll count、post-mix latency、目标行的同步延迟分布。
- `workload drift`：优先看 before/after feature distribution、realized drift factor、query sample diff、feature scope 内各维度的 divergence。

## 5. 多 seed / cross-system / head-to-head 的聚合规则
- 多 seed 结果先按 `seed` 展开，再做均值、标准差、分位数和箱线图，不要把单个 seed 当成稳定结论。
- cross-system 对照必须保持同一逻辑压力与同一 validation contract；如果某个系统缺少观测能力，明确标为 `adapter-limited`。
- head-to-head baseline 优先做 paired comparison：同一 dataset、同一 seed、同一 slice、同一时间窗下比较，避免把不同 run 的时间噪声混进结论。
- 所有聚合结果都要回写到 `figures/`、`tables/` 或 `exp.tex` 的输入草稿中，而不是只保留在临时分析脚本里。

## 6. Phase 5 结果提炼约定
- `results/phase5/seed-sweep-status.tsv`：seed sweep 的执行状态日志。
- `results/phase5/seed-sweep-runlist.txt`：完成的 run-dir 列表。
- `results/phase5/run-index.csv`：逐个 run 的证据索引。
- `results/phase5/seed-summary.csv`：seed-level 聚合表。
- `results/phase5/comparison-index.csv`：cross-system / head-to-head 比较索引。
- `results/phase5/summary.md`：给图表、表格和正文草稿直接复用的人工摘要。

## 7. 重绘入口
- 单 run 自动出图：`exp/scripts/analysis/render_mixed_run_plots.py --run-dir <run_dir>`
- 多 run 对比：`exp/scripts/analysis/render_mixed_compare_plots.py --runlist <runlist> --output-dir <dir>`
- 自动出图只影响图表产物，不覆盖 benchmark 主状态；图表状态写入 `validation/plot-status.json`。
