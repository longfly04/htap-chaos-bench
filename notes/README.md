# notes index

## Current note set
- `internal-zh-outline.md`：项目内部中文总提纲
- `29-run-results-summary.md`：29轮扩展矩阵结果总汇总与主图分组
- `claim-boundary.md`：当前可声称与不可声称的边界
- `related-map.md`：相关工作分桶与差异点
- `problem-formulation.md`：问题定义、输入输出、目标函数与假设
- `experiment-matrix.md`：研究问题与实验切片映射

## Suggested reading order
1. `internal-zh-outline.md`
2. `29-run-results-summary.md`
3. `claim-boundary.md`
4. `problem-formulation.md`
5. `related-map.md`
6. `experiment-matrix.md`

## Maintenance rule
- 29轮矩阵的 canonical run evidence 在 gpu1 远端 `runs/<run>/derived/workload-sql-set.{json,md}`。
- 本地只维护轻量写作镜像：`exp/results/phase5/29-run-matrix/` 与本目录下的总结笔记。
- 任何实质性的 framing 变化，都要同步刷新 `internal-zh-outline.md`。
- 任何新增 claim，都先在 `claim-boundary.md` 里写清楚证据状态。
