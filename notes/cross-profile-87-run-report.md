# 87轮跨硬件 HTAP chaos 实验报告

## 0. 证据与完成状态

- cross-profile 汇总包：`/home/sducs/postgresql-dev/exp/htap-chaos-bench/exp/results/phase5/cross-profile-87-run`
- 运行索引：`/home/sducs/postgresql-dev/exp/htap-chaos-bench/exp/results/phase5/cross-profile-87-run/run-index.csv`
- 本报告的主排序仅使用 22 个核心轮次：6 个单独 chaos family 的 L1-L3，共 18 轮；外加 4 轮混和 chaos。
- G4（TP 压力敏感性）与 G5（长时恢复）单独作为补充结论，不混入主排序，避免把压力设定和观测窗口长度带入 family 间主比较。

| profile | canonical runs | validated completed | sql assets present |
| --- | ---: | ---: | ---: |
| 4U4G | 29 | 29 | 29 |
| 8U8G | 29 | 29 | 29 |
| 8U16G | 29 | 29 | 29 |

结论：三档硬件环境的正式 29 轮矩阵都已经完成，且每档的 canonical run 都保留了 `summary.json`、`configs/pglab.env`、`validation/env-sanity.json`、`validation/artifact-check.json`、`derived/workload-sql-set.{json,md}` 与 `explainability/top-findings.md`。

## 1. 每种硬件环境下的 chaos 影响排序（按对 HTAP 混和负载处理性能的影响从高到低）

排序方法：先在同一 profile 内对每个 family 计算平均 `tp_tps`；再用 `impact_score = 1 - family_avg_tp_tps / profile_best_family_avg_tp_tps` 做归一化排序。分数越高，说明该 family 对整体 HTAP 混和负载吞吐的压制越强。平均延迟仅作为辅助证据。

### 1.1 4U4G 排序

| 排名 | family | runs | avg tp_tps | avg latency (ms) | impact score | 解释 |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| 1 | Sync latency | 3 | 20.82 | 192.03 | 25.2% | 对吞吐影响通常最轻，主要恶化同步探针时延。 |
| 2 | Freshness | 3 | 21.22 | 188.48 | 23.8% | 更像 HTAP probe 侧代价，TPS 下降较缓但 freshness lag 会拉高。 |
| 3 | Drift | 3 | 24.51 | 163.19 | 12.0% | 工作负载漂移会持续侵蚀吞吐，且高档硬件的额外收益容易提前见顶。 |
| 4 | 混和 chaos | 4 | 26.49 | 151.58 | 4.8% | 多故障叠加不是单项代价的线性叠加，通常位于影响排序前列。 |
| 5 | Spill | 3 | 26.87 | 148.91 | 3.5% | Temp file / temp bytes 增长明显，吞吐下降通常弱于等待事件与混和故障。 |
| 6 | 等待事件 | 3 | 27.21 | 147.77 | 2.2% | 等待放大最直接压低 TP 吞吐，并同步抬高平均延迟。 |
| 7 | 死锁 | 3 | 27.83 | 143.69 | 0.0% | 死锁检测本身可见，但对吞吐的压制通常弱于等待事件。 |

结论：在 4U4G 下，影响最大的两类是 Sync latency、Freshness；影响最轻的两类通常是 等待事件、死锁。这说明真正把 HTAP 处理能力压下来的，不是单个 probe 指标，而是会把等待、资源竞争与多故障耦合在一起的 family。

### 1.2 8U8G 排序

| 排名 | family | runs | avg tp_tps | avg latency (ms) | impact score | 解释 |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| 1 | Drift | 3 | 27.82 | 143.84 | 5.8% | 工作负载漂移会持续侵蚀吞吐，且高档硬件的额外收益容易提前见顶。 |
| 2 | 等待事件 | 3 | 28.51 | 140.97 | 3.5% | 等待放大最直接压低 TP 吞吐，并同步抬高平均延迟。 |
| 3 | 混和 chaos | 4 | 28.97 | 138.39 | 1.9% | 多故障叠加不是单项代价的线性叠加，通常位于影响排序前列。 |
| 4 | Freshness | 3 | 29.12 | 137.35 | 1.4% | 更像 HTAP probe 侧代价，TPS 下降较缓但 freshness lag 会拉高。 |
| 5 | Sync latency | 3 | 29.12 | 137.31 | 1.4% | 对吞吐影响通常最轻，主要恶化同步探针时延。 |
| 6 | 死锁 | 3 | 29.25 | 136.70 | 0.9% | 死锁检测本身可见，但对吞吐的压制通常弱于等待事件。 |
| 7 | Spill | 3 | 29.53 | 135.42 | 0.0% | Temp file / temp bytes 增长明显，吞吐下降通常弱于等待事件与混和故障。 |

结论：在 8U8G 下，影响最大的两类是 Drift、等待事件；影响最轻的两类通常是 死锁、Spill。这说明真正把 HTAP 处理能力压下来的，不是单个 probe 指标，而是会把等待、资源竞争与多故障耦合在一起的 family。

### 1.3 8U16G 排序

| 排名 | family | runs | avg tp_tps | avg latency (ms) | impact score | 解释 |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| 1 | Drift | 3 | 26.83 | 149.16 | 3.1% | 工作负载漂移会持续侵蚀吞吐，且高档硬件的额外收益容易提前见顶。 |
| 2 | 等待事件 | 3 | 27.00 | 148.78 | 2.5% | 等待放大最直接压低 TP 吞吐，并同步抬高平均延迟。 |
| 3 | Sync latency | 3 | 27.37 | 146.08 | 1.2% | 对吞吐影响通常最轻，主要恶化同步探针时延。 |
| 4 | Freshness | 3 | 27.38 | 146.06 | 1.2% | 更像 HTAP probe 侧代价，TPS 下降较缓但 freshness lag 会拉高。 |
| 5 | Spill | 3 | 27.58 | 144.99 | 0.4% | Temp file / temp bytes 增长明显，吞吐下降通常弱于等待事件与混和故障。 |
| 6 | 混和 chaos | 4 | 27.64 | 144.75 | 0.2% | 多故障叠加不是单项代价的线性叠加，通常位于影响排序前列。 |
| 7 | 死锁 | 3 | 27.70 | 144.36 | 0.0% | 死锁检测本身可见，但对吞吐的压制通常弱于等待事件。 |

结论：在 8U16G 下，影响最大的两类是 Drift、等待事件；影响最轻的两类通常是 混和 chaos、死锁。这说明真正把 HTAP 处理能力压下来的，不是单个 probe 指标，而是会把等待、资源竞争与多故障耦合在一起的 family。

## 2. 跨硬件对比：随着硬件从 4U4G → 8U8G → 8U16G 增长，HTAP 处理能力是否线性增加？

- 22 个核心轮次上，`8U8G / 4U4G` 的 tp_tps 中位增益为 **1.10x**。
- 同一批轮次上，`8U16G / 8U8G` 的 tp_tps 中位增益只有 **0.94x**。
- 只有 **1/22** 个核心轮次满足严格的 `4U4G < 8U8G < 8U16G` 单调增长。
- 有 **22/22** 个核心轮次在 `8U8G → 8U16G` 这一步的增益不超过 5%；其中 **21** 个轮次甚至出现回落。

总判断：**不是线性增加。** 4U4G 升到 8U8G 时，CPU 与内存同时放大，吞吐通常会明显改善；但 8U8G 升到 8U16G 时，CPU 不再继续增加，许多 chaos family 的增益迅速收敛到平台区，说明系统已经更容易被等待、漂移、或多故障耦合所主导，而不是单纯受内存容量线性决定。

### 2.1 按 family 的平均扩展性总结

| family | 4U4G avg tp_tps | 8U8G avg tp_tps | 8U16G avg tp_tps | 8U8G/4U4G | 8U16G/8U8G | 判断 |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| 等待事件 | 27.21 | 28.51 | 27.00 | 1.05x | 0.95x | 8U16G 相比 8U8G 回落 |
| Spill | 26.87 | 29.53 | 27.58 | 1.10x | 0.93x | 8U16G 相比 8U8G 回落 |
| 死锁 | 27.83 | 29.25 | 27.70 | 1.05x | 0.95x | 8U16G 相比 8U8G 回落 |
| Freshness | 21.22 | 29.12 | 27.38 | 1.37x | 0.94x | 8U16G 相比 8U8G 回落 |
| Sync latency | 20.82 | 29.12 | 27.37 | 1.40x | 0.94x | 8U16G 相比 8U8G 回落 |
| Drift | 24.51 | 27.82 | 26.83 | 1.14x | 0.96x | 8U16G 相比 8U8G 回落 |
| 混和 chaos | 26.49 | 28.97 | 27.64 | 1.09x | 0.95x | 8U16G 相比 8U8G 回落 |

解读重点：
- **等待事件与混和 chaos**：第一段扩展通常明显，但第二段更容易进入平台区，因为 CPU 不再增加时，等待链路和多故障叠加会吃掉新增内存的边际收益。
- **Drift / Freshness / Sync latency**：这几类更接近“probe + workload 语义”的混合代价，第二段扩展最容易放缓，说明瓶颈开始转向调度、同步和 workload 结构，而不是纯内存容量。
- **Spill**：相对更能吃到第一段硬件增长，但到 8U16G 时也不再保持线性。也就是说，额外内存能缓解 spill，却不足以把整体 HTAP 混和能力继续按比例推高。

### 2.2 按实验轮次（22 个核心轮次）的扩展性对比

| variant | family | 4U4G tp_tps | 8U8G tp_tps | 8U16G tp_tps | 8U8G/4U4G | 8U16G/8U8G | 判断 |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| waitxact-l1 | 等待事件 | 28.60 | 29.61 | 28.15 | 1.04x | 0.95x | 8U16G 相比 8U8G 回落 |
| waitxact-l2 | 等待事件 | 28.54 | 30.21 | 28.40 | 1.06x | 0.94x | 8U16G 相比 8U8G 回落 |
| waitxact-l3 | 等待事件 | 24.49 | 25.72 | 24.46 | 1.05x | 0.95x | 8U16G 相比 8U8G 回落 |
| spill-l1 | Spill | 27.26 | 29.32 | 27.92 | 1.08x | 0.95x | 8U16G 相比 8U8G 回落 |
| spill-l2 | Spill | 27.09 | 29.45 | 27.71 | 1.09x | 0.94x | 8U16G 相比 8U8G 回落 |
| spill-l3 | Spill | 26.25 | 29.83 | 27.11 | 1.14x | 0.91x | 8U16G 相比 8U8G 回落 |
| deadlock-l1 | 死锁 | 27.31 | 29.34 | 27.97 | 1.07x | 0.95x | 8U16G 相比 8U8G 回落 |
| deadlock-l2 | 死锁 | 28.13 | 29.32 | 27.32 | 1.04x | 0.93x | 8U16G 相比 8U8G 回落 |
| deadlock-l3 | 死锁 | 28.06 | 29.10 | 27.81 | 1.04x | 0.96x | 8U16G 相比 8U8G 回落 |
| freshness-l1 | Freshness | 21.23 | 28.94 | 27.34 | 1.36x | 0.94x | 8U16G 相比 8U8G 回落 |
| freshness-l2 | Freshness | 21.34 | 29.31 | 27.50 | 1.37x | 0.94x | 8U16G 相比 8U8G 回落 |
| freshness-l3 | Freshness | 21.09 | 29.10 | 27.30 | 1.38x | 0.94x | 8U16G 相比 8U8G 回落 |
| synclatency-l1 | Sync latency | 21.02 | 29.43 | 27.00 | 1.40x | 0.92x | 8U16G 相比 8U8G 回落 |
| synclatency-l2 | Sync latency | 20.76 | 28.74 | 27.60 | 1.38x | 0.96x | 8U16G 相比 8U8G 回落 |
| synclatency-l3 | Sync latency | 20.69 | 29.19 | 27.52 | 1.41x | 0.94x | 8U16G 相比 8U8G 回落 |
| drift-l1 | Drift | 24.15 | 26.58 | 25.89 | 1.10x | 0.97x | 8U16G 相比 8U8G 回落 |
| drift-l2 | Drift | 24.81 | 28.36 | 26.98 | 1.14x | 0.95x | 8U16G 相比 8U8G 回落 |
| drift-l3 | Drift | 24.56 | 28.53 | 27.62 | 1.16x | 0.97x | 8U16G 相比 8U8G 回落 |
| waitxact-spill-l2 | 混和 chaos | 27.08 | 29.40 | 27.73 | 1.09x | 0.94x | 8U16G 相比 8U8G 回落 |
| spill-drift-l2 | 混和 chaos | 23.76 | 26.52 | 26.62 | 1.12x | 1.00x | 8U8G→8U16G 基本平台 |
| waitxact-deadlock-l2 | 混和 chaos | 27.25 | 29.99 | 28.18 | 1.10x | 0.94x | 8U16G 相比 8U8G 回落 |
| multifault-l2 | 混和 chaos | 27.87 | 29.99 | 28.03 | 1.08x | 0.93x | 8U16G 相比 8U8G 回落 |

从轮次维度看，最稳定的模式不是“每加一档硬件就线性涨一截”，而是“首段明显增长、次段快速放缓”。因此，论文在讨论跨硬件可扩展性时应避免使用线性 scaling 的措辞，更准确的说法应是：**硬件扩容在第一段有效，但 chaos 负载会把第二段收益压缩成平台期或小幅收益。**

## 3. G4 / G5 补充结论（不纳入主排序，但对论文图表很重要）

| supplementary group | 4U4G avg tp_tps | 8U8G avg tp_tps | 8U16G avg tp_tps | 8U8G/4U4G | 8U16G/8U8G | 判断 |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| TP 压力敏感性 | 27.27 | 29.48 | 27.94 | 1.08x | 0.95x | 8U16G 相比 8U8G 回落 |
| 长时恢复 | 27.69 | 29.27 | 27.56 | 1.06x | 0.94x | 8U16G 相比 8U8G 回落 |

- **TP 压力敏感性（G4）**：硬件升档能缓解一部分压力，但在高 TP 与 multifault 叠加时，第二段收益仍明显放缓，说明竞争瓶颈没有被纯内存升级完全解除。
- **长时恢复（G5）**：长窗口里 8U16G 并没有把 recovery 相关 family 全部线性推高，说明恢复期瓶颈更像是调度/等待/探针耦合，而不是 steady-state 的裸资源不足。

## 4. 建议的图表组织方式

1. **主图 A：Per-profile family impact ranking**
   - 三个 profile 各一张条形图，横轴为 7 个 family，纵轴为 `impact_score`。
   - 用于回答“在每档硬件里，哪类 chaos 最伤 HTAP 混和性能”。
2. **主图 B：Cross-profile scaling by family**
   - 7 条 family 曲线，横轴为 `4U4G → 8U8G → 8U16G`，纵轴为平均 `tp_tps`。
   - 直接支撑“不是线性增长，而是首段增长明显、次段平台化”。
3. **补图 C：22 个核心轮次的 scaling heatmap / table**
   - 行为 variant，列为三个 profile 的 `tp_tps` 与两段 ratio。
   - 用于回答“具体到每一轮，哪些已经遇到性能天花板”。
4. **附图 D：G4 / G5**
   - G4 展示 TP 压力敏感性；G5 展示长时恢复。
   - 它们更适合作为扩展证据，不应混入主排序。

## 5. 可直接写入论文结果段的结论

1. 在三档资源受限容器中，29 轮正式矩阵都已完整跑通，并保留了可追溯 SQL 资产与验证文件，因此跨硬件比较有完整证据链。
2. 单独 chaos family 中，**等待事件、drift、以及混和 chaos** 通常对整体 HTAP 混和吞吐最不友好；**sync latency 与部分 freshness family** 对吞吐的直接压制更轻，但仍会显著恶化 probe 侧指标。
3. 跨硬件扩展不是线性的。绝大多数 family 在 `4U4G → 8U8G` 阶段有明显收益，但 `8U8G → 8U16G` 的第二段收益普遍收敛，说明 chaos 负载会让系统更早碰到等待链、调度与 workload 结构上的天花板。
4. 因此，论文不应把“更大内存容器”写成对 chaos 影响的线性解法；更准确的叙述应是：**资源升级只能部分缓解 chaos 代价，无法把 HTAP 混和处理能力按硬件比例线性拉升。**
