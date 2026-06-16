# 内部中文总提纲

## 1. Working title
- HTAP mixed-load chaos benchmark: selective fault pressure, HTAP freshness, and long-horizon recovery

## 2. 一句话主线
- 这篇工作不讨论通用控制器设计，而是用一个可复现实验矩阵证明：在 JOB 风格 HTAP 混合负载下，不同 chaos 故障、故障叠加、TP 压力变化与长时恢复窗口会呈现结构化且可量化的性能/新鲜度/恢复差异。

## 3. 当前问题 framing
- 问题对象：PostgreSQL-like HTAP 混合负载在故障注入、负载漂移与恢复观察下的行为画像。
- 当前痛点：已有实验往往只给单点故障或短窗口结果，缺少把 TP、AP、HTAP-check、chaos SQL 资产与结果表一一对齐的完整证据链。
- 为什么已有方法不够：只给聚合指标会让 workload 语义、probe 语义与故障注入动作不可追溯，论文写作时难以严格界定 claim 边界。
- 计划收敛到的切口：围绕 29 轮扩展矩阵，建立“主图分组 + 每轮 SQL 资产 + 结果包”的可复用证据层。

## 4. 当前方法/系统主张
- 核心机制：把 TP/AP/probe/chaos 的实际 SQL 集合直接固化进每个 canonical run-dir，并基于统一脚本生成 29 轮结果表、family summary 与主图分组。
- 与现有系统的最关键区别：不是只导出指标，而是把实验语义资产化，允许从论文表格追溯到每一轮真实 workload SQL。
- 当前最有把握的创新点：证据组织方式严谨，适合支撑 benchmark / experimental discovery 型论文叙事。

## 5. 当前实验主线
- 主平台：gpu1 远端 `/home/sducs/postgresql-dev/exp/htap-chaos-bench`，source runtime PostgreSQL 17.4。
- 主 workload / 数据路径：JOB 数据集；TP 为 `derived/tp-template-resolved.sql` 物化更新流，AP 以 sort-heavy 为主并覆盖 drift sample，HTAP probe 覆盖 freshness / sync-latency。
- 关键指标：`tp_tps`、`tp_latency_avg_ms`、`freshness_latest_lag_ms`、`sync_post_ms`、`wait_duration_ms`、`deadlock_detected_count`、`spill_temp_bytes_delta`、`workload_drift_realized_factor`、`recovery_time_ms`。
- 当前 canonical evidence：
  - 远端每轮 run-dir 下 `derived/workload-sql-set.json` 与 `derived/workload-sql-set.md`
  - 远端汇总包 `exp/results/phase5/29-run-matrix/`
  - 本地写作镜像 `notes/29-run-results-summary.md`

## 6. 相关工作分桶
- 桶 A：故障注入 / chaos benchmarking for OLTP or DB runtime。
- 桶 B：HTAP freshness / staleness / sync-latency 观测。
- 桶 C：混合负载、workload drift 与长时恢复行为分析。
- 我们与每一桶的边界：重点不是提出新数据库内核机制，而是给出一套可追溯、可复现、可直接用于论文主图组织的扩展实验矩阵证据层。

## 7. 当前风险
- 论证风险：当前更适合“实验发现/benchmark 资产化”叙事，不宜过度外推为普适理论。
- 实现风险：远端 canonical run-dir 是主证据，后续同步必须继续保持项目级单向脚本同步，避免覆盖远端结果。
- 实验风险：family summary 目前是单 seed 结果，不应过度表述统计稳健性。
- 过度表述风险：不能声称提出了新的 fault-tolerance algorithm，只能声称构建了系统化矩阵与可追溯证据链。

## 8. 下一步
1. 基于 `exp/results/phase5/29-run-matrix/results-table.csv` 与 `figure-groups.md` 起草论文正文实验段落。
2. 在 `claim-boundary.md` 中把当前能支撑/不能支撑的 claim 明确列出来。
3. 如需补实验，只在缺口明确的 family 上增量扩展，而不是重跑整套 29 轮矩阵。
