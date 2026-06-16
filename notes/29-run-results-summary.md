# 29轮扩展矩阵结果总汇总

## 1. 结果包与证据位置

### 1.1 canonical evidence
- 远端 canonical run 目录：`/home/sducs/postgresql-dev/exp/htap-chaos-bench/runs/<run-id>/`
- 每轮 SQL 资产：`derived/workload-sql-set.md`
- 每轮 SQL 结构化资产：`derived/workload-sql-set.json`
- 29轮汇总包：`/home/sducs/postgresql-dev/exp/htap-chaos-bench/exp/results/phase5/29-run-matrix/`

### 1.2 本地写作镜像
- `Papers/Projects/htap-chaos-bench/notes/internal-zh-outline.md`
- `Papers/Projects/htap-chaos-bench/notes/29-run-results-summary.md`

### 1.3 汇总包文件
- `runlist.txt`
- `run-index.csv`
- `results-table.csv`
- `seed-summary.csv`
- `comparison-index.csv`
- `family-summary.csv`
- `figure-groups.md`
- `summary.md`
- `summary.json`

当前状态：29/29 轮 run 已纳入汇总，29/29 轮 run 已生成 SQL 资产。

## 2. 29轮矩阵如何分组

### G2：HTAP-check 与 workload drift 观察组（18轮）
- 覆盖对象：单故障 wait_xact / spill / deadlock 的 L1-L3，freshness L1-L3，sync-latency L1-L3，drift L1-L3。
- 推荐主指标：`tp_tps`、`tp_latency_avg_ms`、`freshness_latest_lag_ms`、`sync_post_ms`、`workload_drift_realized_factor`。
- 解读重点：
  - wait_xact 强度升高会显著推高等待时间，并拖低 TP 吞吐。
  - spill 压力主要体现在 temp bytes 放大，同时 freshness lag 仍会被拉高。
  - deadlock 类 run 的主要异常体现在 deadlock 检测与 freshness lag，而非 spill 指标。
  - drift 与 heavy-drift 组把 AP 从固定 SQL 切换为 materialized drift sample，因此 SQL 资产必须跟随 run-dir 一起看。

### G3：多故障叠加组（4轮）
- 覆盖对象：`waitxact+spill`、`spill+drift`、`waitxact+deadlock`、`multifault`。
- 推荐主指标：`tp_tps`、`tp_latency_avg_ms`、`wait_duration_ms`、`deadlock_detected_count`、`spill_temp_bytes_delta`、`workload_drift_realized_factor`。
- 解读重点：
  - 多故障叠加并不只是单故障线性相加，不同 primitive 会把等待、spill、freshness 三类代价耦合到一起。
  - `multifault` 与 `waitxact+deadlock` 是当前最能体现“恢复前期间代价叠加”的两组代表。

### G4：TP 压力敏感性组（3轮）
- 覆盖对象：`spill-l2-lowtp`、`spill-l2-hightp`、`multifault-l2-hightp`。
- 推荐主指标：`tp_tps`、`tp_latency_avg_ms`、`spill_temp_bytes_delta`、`wait_duration_ms`、`deadlock_detected_count`。
- 解读重点：
  - 在当前配置下，TP 压力变化对 spill / multifault 结果有明显影响，但仍要结合具体 AP SQL 与 probe SQL 理解其边界。

### G5：长时恢复组（4轮）
- 覆盖对象：`spill-l3-long`、`waitxact-l3-long`、`multifault-l2-long`、`drift-heavy-long`。
- 推荐主指标：`tp_tps`、`tp_latency_avg_ms`、`recovery_time_ms`、`wait_duration_ms`、`spill_temp_bytes_delta`、`sync_post_ms`、`workload_drift_realized_factor`。
- 解读重点：
  - 长时组的主要价值在于把恢复窗口与 steady-state 区分开，而不是只看短窗口峰值。
  - `drift-heavy-long` 同时带有 drift sample 与 sync-latency probe，适合作为 workload 变化与恢复观测交叉点。

## 3. 每组实验使用的标志性 SQL 集合

### 3.1 TP SQL
29轮 run 的 TP 主更新流都以各自 run-dir 下的 `derived/tp-template-resolved.sql` 为准。其核心语义是：
- 在 `movie_freshness` 上按 hot range 选取热点 movie_id；
- 对这些行执行 `epoch = epoch + 1`、`hot_flag = true`、`freshness_score = freshness_score + 1`、`last_touch_ts = now()`；
- 不同 run 的差异主要体现在 `hot_modulus`、`hot_remainder`、`batch_size`、threads / terminals / driver。

### 3.2 AP SQL
- 固定 AP 主线：`sort-heavy-q001.sql` 为主；部分组也伴随 `hash-heavy`、`mixed` 或 class pool 背景。
- drift 相关 run：实际 AP SQL 不再是固定文件，而是每轮自己的 `derived/query-drift-sample.sql`。
- 因此，凡是 drift / heavy-drift 相关实验，论文中都应引用该 run 自己的 `workload-sql-set.md`，不能只写抽象 class 名称。

### 3.3 HTAP probe SQL
- freshness 类：`derived/freshness-probe.sql`
- sync-latency 类：`derived/sync-latency-probe.sql`
- 这两类 probe 的元数据分别写在 `freshness-profile.json` 与 `sync-latency-profile.json` 中，已被纳入每轮 SQL 资产。

### 3.4 chaos SQL
- `wait_xact`：资产里给出 blocker / waiter 的实际 SQL 模板。
- `deadlock_pair`：资产里给出 session A / session B 的实际 SQL 模板。
- `spill_pressure`：资产里给出 `SET work_mem = ...; <ap_query>` 形式的组合 SQL。
- `multi-fault`：资产按注入顺序展开每个子 primitive，而不是只保留最终汇总标签。

## 4. 主图分组建议

### Main Fig. G2
- 标题：HTAP-check and drift observation
- 适合放正文最前，因为它覆盖单故障基础线、freshness、sync-latency 与 drift 主线。
- 推荐强调：
  - wait_xact L1→L3 的等待放大；
  - spill L1→L3 的 temp bytes 放大；
  - drift / heavy-drift 对 freshness 与 sync 的影响；
  - 同一 family 下 SQL 资产可直接回溯。

### Main Fig. G3
- 标题：Multi-chaos stacking
- 用于说明 fault stacking 不是简单叠加，而是 workload / probe / chaos 联合作用。

### Main Fig. G4
- 标题：TP pressure sensitivity
- 用于说明相同 chaos family 在 TP 压力变化下的敏感性。

### Main Fig. G5
- 标题：Long-duration recovery
- 用于说明长时间窗口下的恢复与稳态差异。

## 5. 当前可直接引用的代表性结果

### 5.1 wait_xact 强度增加时的代价
- `waitxact-l1`：`tp_tps=7.28`，`wait_duration_ms=6102`
- `waitxact-l2`：`tp_tps=5.98`，`wait_duration_ms=28082`
- `waitxact-l3`：`tp_tps=4.27`，`wait_duration_ms=58153`

可支撑结论：随着 wait_xact 强度增加，等待代价显著上升，同时 TP 吞吐明显下降。

### 5.2 spill 类故障的主要症状
- `spill-l1`：`spill_temp_bytes_delta=2136207832`
- `spill-l2`：`spill_temp_bytes_delta=71803680`
- `spill-l3`：`spill_temp_bytes_delta=72215168`

可支撑结论：spill 类故障最直接的外显指标是 temp bytes 放大，并且会伴随 freshness lag 上升。

### 5.3 多故障叠加的代表结果
- `waitxact-spill-l2`：同时存在较高 wait duration 与显著 spill bytes。
- `waitxact-deadlock-l2`：同时出现长等待与 deadlock 检测。
- `multifault-l2`：同时出现 wait、deadlock 与 spill 指标。

可支撑结论：多故障叠加后，系统行为不能用单一 primitive 指标解释，必须联动看 TP/AP/probe/chaos SQL 资产。

### 5.4 长时恢复的代表结果
- `spill-l3-long`：`tp_tps=7.93`，`spill_temp_bytes_delta=98304000`
- `waitxact-l3-long`：`tp_tps=7.24`，`wait_duration_ms=58191`
- `multifault-l2-long`：`tp_tps=7.93`，`deadlock_detected_count=1`
- `drift-heavy-long`：`tp_tps=7.63`，`sync_post_ms=43`，`workload_drift_realized_factor=0.490797`

可支撑结论：长时组给出了故障后恢复窗口与 steady-state 的区分证据，适合单列一组主图。

## 6. claim 边界

### 当前能支撑的 claim
- 29轮扩展矩阵已经形成可复现实验资产，且每轮 workload SQL 可追溯。
- 单故障、多故障、TP 压力变化与长时恢复可以被统一整理到同一结果包下。
- 对 drift / heavy-drift 类 run，实际 AP SQL 与固定 AP 文件不同，必须按 run-dir 资产解释结果。

### 当前只能部分支撑的 claim
- 不同 family 之间的绝对优劣比较。因为当前更多是行为画像，不是严格 controlled causal proof。
- 某类故障在所有 HTAP 系统上的普适规律。当前平台仍是 pg-like + JOB 语义。

### 当前不能支撑的 claim
- 新数据库机制优于现有系统的普适结论。
- 多 seed 统计稳健性结论。
- 对所有 workload family 的理论保证。

## 7. 后续写作建议
- 正文实验部分按 `G2 -> G3 -> G4 -> G5` 组织，不建议按执行时间顺序写。
- 每个主图 family 在正文首次出现时，补一句“其对应 SQL 资产位于 canonical run-dir 的 `derived/workload-sql-set.md`”。
- 如果需要补实验，优先补单个 family 的 seed 或压力点，而不是重跑整套矩阵。
