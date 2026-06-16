# paper1 experiment workspace

本目录承载 `paper1-memhtap-benchmark` 的实验执行层，而不是论文正文。

## 当前目标
- 用 `pg-like + JOB` 先闭合 Phase 0.5 / Phase 1 / Phase 2 的最小可执行环。
- 统一使用本项目内置的 harness 脚本作为 runtime、run-dir 与 artifact contract，不再依赖外部共享脚本目录。
- 使用项目根目录下的 `pglab/` 和 `config/site.env` 作为远程环境首选入口，不再借用 `paper3-memory-scheduling/pglab`。
- 先把 baseline、validation、generator smoke 做稳，再扩到 `STAT-CEB`、cross-system、multi-fault，随后进入 multiple seeds、head-to-head baseline 与图表/表格提炼阶段。
- Phase 5 现在进入 evidence closure：seed sweep、cross-system pilot、head-to-head baseline，以及 run-dir 证据提炼脚本都要可复用。
- mixed run 现在需要同时产出时间序列观测与图表产物：`observability/timeline/` 下的采样 CSV/JSONL、`validation/plot-status.json`、以及 `figures/` 下的高清大图 / 联排图。
- 单 run 自动出图入口为 `exp/scripts/analysis/render_mixed_run_plots.py`；多 run 对比重绘入口为 `exp/scripts/analysis/render_mixed_compare_plots.py`。
- `exp/scripts/run/run_phase5_seed_sweep.sh` 现在要求 phase5 源 manifest 显式提供 `SEED=`；paired comparison 可用 `exp/scripts/run/run_phase5_pair.sh` 跑成对 baseline/candidate。
- richer scenarios 现已补充 `manifests/phase5/go-mixed-multifault-mainline.env` 与 `manifests/phase5/go-mixed-workload-drift-heavy.env`，分别覆盖 multi-fault orchestration 和更强 workload-drift + HTAP 观测。

## 推荐分层
- `ops/`：执行矩阵、采样规范、执行清单
- `manifests/`：smoke、baseline、generator slice manifests
- `adapters/pg-like/`：pg-like capability、plan capture、temp/spill metrics
- `datasets/job/`：schema、snapshot、stats、AP class、TP template 资产
- `scripts/`：prepare、run、validation
- `sql/`：validation、observability、baseline 查询
- `specs/`：`memory-tiers.yaml`、`tp-pressure-tiers.yaml`、`lock-severity.yaml`
- `generator/`：stats export、schema graph、template、drift、scenario instantiation
- `results/`：项目级原始与派生结果索引
- `runs/`：本地 run-dir 根目录

## 默认顺序
0. 先复制并填写 `../config/site.env.example -> ../config/site.env`；容器模式还要复制 `../pglab/compose/.env.example -> ../pglab/compose/.env`。
1. 先读 `../notes/internal-zh-outline.md`、`../notes/cross-system-multi-dataset-scenario-contract.md`、`../notes/validation-scripts-checklist.md`。
2. 从项目根目录执行，先跑 shared dry-run 与 paper1 smoke。
3. 再跑 TP-only baseline、AP-only baseline、lock baseline。
4. 然后推进 mixed 语义层、seed sweep 与 evidence extraction。
5. 最后把 run-dir 产物同步回 `../notes/internal-zh-outline.md` 与正文草稿。
6. Phase 5 结果汇总优先写到 `results/phase5/`，再回填图表和表格草稿。
