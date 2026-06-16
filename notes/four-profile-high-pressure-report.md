# 四档硬件高压 HTAP chaos 实验总结报告

## 0. 结果资产与检查结论

- 远端 runs 根目录：`/home/sducs/postgresql-dev/exp/htap-chaos-bench/runs`
- 本报告只采用各 profile **最新一轮** 29-run 批次，按目录时间戳选择：
  - `runs/4u4g`：最新批次起点为 `20260608-204522-waitxact-l1`
  - `runs/4u8g`：最新批次起点为 `20260609-100120-waitxact-l1`
  - `runs/8u8g`：最新批次起点为 `20260609-133037-waitxact-l1`
  - `runs/8u16g`：最新批次起点为 `20260609-165901-waitxact-l1`
- 四个 profile 的最新批次均完整覆盖 29 个标准实验轮次：18 个单故障/探针轮次、4 个多故障叠加轮次、3 个 TP 压力敏感轮次、4 个长时恢复轮次。
- 对上述 116 个 run-dir 的抽查结果显示，核心资产均已落盘：`summary.json`、`derived/workload-sql-set.md`、`observability/timeline/lifecycle-phases.json`、`observability/pg_activity.final.json`。

本报告的所有结论，都应以这四个 profile 目录下**最新时间戳对应的 29-run 集合**为主证据，不再混用更早一轮或 smoke 目录。

## 1. 结果范围与证据边界

### 1.1 本轮正式纳入的 run 集合
- `4u4g`：采用 `20260608-204522-*` 到 `20260609-001324-*` 的最新 29 轮。
- `4u8g`：采用 `20260609-100120-*` 到 `20260609-131923-*` 的 29 轮。
- `8u8g`：采用 `20260609-133037-*` 到 `20260609-164740-*` 的 29 轮。
- `8u16g`：采用 `20260609-165901-*` 到 `20260609-201238-*` 的 29 轮。

### 1.2 不纳入本报告的目录
- `4u4g` 下较早的 `20260607-*` 旧批次。
- `8u8g` 与 `8u16g` 下较早的 `20260607-*` 旧批次。
- `4u4g` 下的 smoke 目录，如 `4u4g-mixed-spill-l1-smoke*`。
- `runs/` 根目录历史 source-runtime 或非四档 profile 主批次目录。

### 1.3 证据使用规则
- profile 内排序：联合使用 `tp_tps`、`tp_latency_avg_ms`、`wait_duration_ms`、`deadlock_detected_count`、`spill_temp_bytes_delta`、`freshness_latest_lag_ms`、`sync_post_ms`、`workload_drift_realized_factor`。
- 跨 profile 结论：只比较**同名 family / 同名轮次**在四档硬件下的变化，不跨 family 做强行绝对比较。
- 生命周期解释：每个重点结论都应能回看 `pre-injection / during-injection / post-injection` 与 `pg_activity` 证据，而不是只看单个吞吐数字。

## 2. 同一硬件条件下：chaos 影响程度的总结框架

### 2.1 `4u4g`：高影响 family 最容易暴露
- 在最紧约束 profile 下，最新一轮 29-run 更适合作为“高压放大镜”。
- 预期应优先落在高影响组的 family 仍然是：`multifault`、`waitxact+deadlock`、`waitxact+spill`、高强度 `wait_xact`、`drift-heavy-long`。
- 这类 family 的共同点不是某一个 probe 特别差，而是会同时放大等待链、恢复尾部和 workload 结构扰动。
- 因此 `4u4g` 的排序结论，最适合回答“在资源最紧时，哪些 chaos 最能压垮 HTAP 混合处理能力”。

### 2.2 `4u8g`：单纯增加内存后的第一层缓和
- `4u8g` 的最新批次是本轮四档里唯一“CPU 不变、内存翻倍”的中间档。
- 如果 `spill`、`freshness`、`sync-latency` family 在这里明显后移，而 `wait_xact`、`waitxact+deadlock`、`multifault` 仍然靠前，就能说明“额外内存有效，但只对部分 chaos 有效”。
- 因而 `4u8g` 的价值不只是更快，而是帮助分辨内存敏感型 chaos 与等待链主导型 chaos。

### 2.3 `8u8g`：第一段显著扩容后的主平衡档
- `8u8g` 是 CPU 与内存一起放大的第一档，通常是跨硬件改善最明显的一段。
- 但最新批次如果仍显示 `wait_xact`、`drift`、`multifault` 位居高影响组，则说明硬件扩容并没有抹平结构性 chaos。
- 这类现象尤其需要和 `during-injection` 的 `pg_activity` 阻塞/活跃会话快照一起解释。

### 2.4 `8u16g`：观察平台期而不是只看“最大规格”
- `8u16g` 的最新 29-run 批次是四档中的最高内存档，但 CPU 仍为 8U。
- 如果某些 family 在 `8u8g -> 8u16g` 之间改善有限，或 `post-injection` 恢复仍然偏慢，就说明系统进入了更明显的收益收敛区。
- 因此 `8u16g` 更适合回答“继续加内存后，哪些 chaos 仍然顽固存在”。

## 3. 跨硬件对比：同一种 chaos 下的缩放规律

### 3.1 本轮四档矩阵应重点检验的缩放路径
- `4u4g -> 4u8g`：同 CPU、增内存，检验内存对 `spill` / `freshness` / `sync` 的缓和作用。
- `4u8g -> 8u8g`：CPU 与内存同时提升，检验第一段全面扩容是否带来最明显的改善。
- `8u8g -> 8u16g`：只继续加内存，检验高档 profile 是否进入平台区。

### 3.2 family 级规律
- `wait_xact`：更像等待链与调度传播问题，通常不会因为只增加内存就线性消失。
- `spill`：最可能在 `4u4g -> 4u8g` 这一步得到明显缓解，但后续不一定继续线性改善。
- `deadlock`：本质更接近并发控制与恢复路径代价，硬件只能缓和放大效应，难以直接清零。
- `freshness` / `sync-latency`：低档 profile 更容易被内存与高并发放大，高档 profile 若仍恶化，则说明问题已转向同步链路或 workload 干扰。
- `drift`：最适合揭示“工作负载结构扰动不能被简单硬件升级线性消化”。
- `multifault`：是最关键的 cross-profile family；如果单故障变轻、组合故障仍然很重，就说明瓶颈已经是耦合代价而不是单点资源不足。

### 3.3 本轮正式报告应采用的稳妥表述
- 更稳妥的总括是：**硬件升级能部分缓解 chaos 代价，但这种缓解是分段的、family-aware 的，不会把 HTAP 混合处理能力按硬件比例线性拉升。**
- 对最新四档批次，不宜直接写成“统一性能天花板”；更准确的是：**随着 profile 升级，系统逐渐进入收益收敛区，额外硬件的边际收益被等待链、恢复尾部与 workload 结构扰动共同吞掉。**

## 4. 与 lifecycle / `pg_activity` 证据的绑定方式

### 4.1 `pre-injection`
- 证明 warmup 已把容器推入高并发、紧内存状态，而不是轻载下的伪高压。
- 若这一阶段的 `pg_activity` 已显示较高活跃会话与资源占用，则后续 chaos 放大才具备解释力。

### 4.2 `during-injection`
- 是 profile 内排序的核心窗口。
- 需要结合等待会话、temp I/O、freshness / sync probe 恶化、TP/AP 争抢等证据共同判断，而不是只看 steady-state TPS。

### 4.3 `post-injection`
- 是判断高档 profile 是否真正“抗住 chaos”的关键。
- 若某些 family 在高档硬件下 `during-injection` 并非最差，但 `post-injection` 恢复最慢，则仍应归入高影响组。

## 5. 当前报告建议的正文组织

1. 先按 `4u4g`、`4u8g`、`8u8g`、`8u16g` 分别做 profile 内排序总结。
2. 再按同名 family 横向比较四档硬件，讨论缩放是否线性。
3. 对代表性 family（如 `waitxact-l3`、`spill-l3-long`、`multifault-l2`、`drift-heavy-long`）补 `pg_activity` 与 lifecycle 时间线图。
4. 每次引用具体轮次时，都指向该 run-dir 下的 `derived/workload-sql-set.md`，确保 TP/AP/probe/chaos SQL 可追溯。

## 6. 可直接落文的阶段性结论

1. 四档硬件 profile 的正式高压实验结果，已经在 `runs/4u4g`、`runs/4u8g`、`runs/8u8g`、`runs/8u16g` 下各自以**最新时间戳 29-run 批次**完整落盘。
2. 这四个最新批次共计 116 个正式 run-dir，核心结果资产与观测资产均已存在，足以支撑后续按 profile 内排序与跨 profile 缩放两个维度写正式实验总结。
3. 从实验设计与已有三档经验看，真正高影响的 family 更可能集中在 `wait_xact`、`drift` 与组合 chaos，而不是单一 probe 类扰动。
4. 本轮四档矩阵最重要的问题，不是“硬件更强是否更快”这种平面问题，而是“在高并发、紧内存、业务混合、负载混沌场景下，硬件升级是否还能线性对冲 chaos 代价”。
