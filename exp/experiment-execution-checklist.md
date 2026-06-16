# paper1 experiment execution checklist

## Phase 0.5 shared closure
- [ ] shared dry-run manifest 可用
- [ ] `summary.json` 含 canonical run identity
- [ ] iteration hygiene helper 可执行
- [ ] lock observation helper 可执行

## Phase 1 smoke
- [ ] `job-pg-smoke.env` dry-run 通过
- [ ] runtime 能启动
- [ ] P0 validation 全通过
- [ ] artifact 结构完整

## Phase 1 baselines
- [ ] TP-only low / medium / high
- [ ] AP-only sort-heavy 先闭合
- [ ] AP-only hash-heavy / mixed 补齐
- [ ] lock / wait baseline 闭合

## Phase 2 generator smoke
- [ ] stats export smoke
- [ ] schema graph smoke
- [ ] SELECT template smoke
- [ ] update / drift smoke
- [ ] instantiate scenario smoke

## Phase 3 evidence closure
- [ ] 稳定点按默认 5 seeds 跑完
- [ ] cross-system pilot 方案写清楚并落到 manifest/contract
- [ ] head-to-head baseline 对照组定义清楚
- [ ] run-dir evidence 汇总脚本或笔记可复用
- [ ] figure / table 输入草稿已准备

## Phase 4 manuscript sync
- [ ] `tp-pressure-tiers.yaml` 回填到图表草稿
- [ ] `memory-tiers.yaml` 回填到图表草稿
- [ ] `lock-severity.yaml` 回填到图表草稿
- [ ] drift / freshness / sync 的 evidence panel 已固定
- [ ] `exp.tex` 已挂上对应图表与表格占位

## Phase 5 evidence closure
- [x] `seed-sweep-workload-drift.env` 可直接复用为多 seed 模板
- [x] `cross-system-workload-drift.env` 可作为 adapter-limited 过渡模板
- [x] `head-to-head-workload-drift.env` 可作为基线对照模板
- [x] `scripts/run/run_phase5_seed_sweep.sh` 可批量跑 run_slice
- [x] `scripts/run/run_phase5_pair.sh` 可跑 paired head-to-head / cross-system 对照
- [x] `scripts/analysis/phase5_evidence_summary.py` 可汇总 run-dir evidence
- [ ] mixed run 自动采样产物（`observability/timeline/*.csv|jsonl`）已生成
- [ ] `validation/plot-status.json` 已写出且状态正确
- [ ] `figures/run-overview.png` 与 `figures/run-panels.png` 已生成
- [ ] 离线 `render_mixed_run_plots.py --run-dir <run>` 可重绘
- [ ] `render_mixed_compare_plots.py --runlist <runlist>` 可生成跨实验对比图
- [x] `results/phase5/summary.md` 可直接喂给图表 / 表格草稿
- [x] richer scenario manifests 已补上 multi-fault 与 heavy workload-drift 入口
