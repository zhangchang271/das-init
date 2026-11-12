# 工作约定

修改或迁移科学计算前，先读 [docs/CONTRACT.md](docs/CONTRACT.md)。
每一步必须交代提取的信息、物理含义、输入输出变量、维度、轴、单位和下一步接口。
不能只列函数名称，也不能仅凭图形相似判断实现正确。

当前已确认行为：

- MATLAB 波形是时间 × 道，CCF 频谱是频率 × 道对 / 距离，F-J 是速度 × 频率。
- 600 s 是输入相关窗；±1 s 是最终 CCF 保存 / 展示窗口，不截短 F-J 输入。
- 正负时间两支对应平均得到半支，可选 mute 后恢复对称记录，再 FFT 输入 F-J。
- PSD 分母是当前窗有效阵列的平均功率谱；叠加保留每对有效窗数。
- F-J 用 H2 / No-window，展示量是 `abs(real(FJ.dsp))`；ridge 用 findpeaks 趋势追踪。
- 逐道 RMS 归一化和色阶裁剪只用于显示；不能悄悄加入白化、one-bit 或偏移增益。

实际函数接口、FFT 缩放及已知端点一致性限制以 CONTRACT 为准；不要按理论点数擅自补点。
已确认的真实 50 道输入、参考结果和中间检查点见 `docs/demo/` 与 `data/demo_sanjose_50ch/`。
待验收结果与参考文件分开保存；不要覆盖参考结果后再声称对照通过。

同输入同算法的部署验收：

```bash
bash scripts/run.sh configs/demo_small.json preview
```

```matlab
addpath('scripts');
report = validate_demo;
```

明确报告验收范围。当前基准覆盖筛选、稀疏原生 CCF 与最终 CCF / 频散观测；
不等于多日收敛、复数 F-J、人工 mask、最终衰减或 Vs / Q / Sw 反演已验证。
