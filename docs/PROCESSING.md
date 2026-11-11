# 计算流程

## 来源与改动

原正式主控为 `SJDASTest/run_sjdas_dasqt_mccfjflow2manual.m`，结构参考
`NyHtQInv/mainline6p0/MCCFJFLOW2Manual.m`。两份原 SJDAS 入口脚本的 SHA-256 记录在
`vendor/manifest.json`，本部署包没有修改原项目。

本包把主控改成接收配置的函数，移除原机器绝对路径，增加阶段入口、环境检查、运行记录和缓存身份检查。
`vendor/matlab` 中的 `mCCFJ`、`EDWav`、`GW_mute`、`GW_mute1` 以及四个 DASQt 后端源文件
按字节保存。DASQt 包的 `__init__.py` 改用最小命名空间，避免导入与此计算无关的 GUI 和读取器；
所调用的处理函数没有改写。

## 默认振幅处理历史

1. 原始数据按连续完整 600 s 片段读取，Python 处理前转为 float32「通道 × 时间」。
2. DASQt 逐道去均值、线性去趋势、Tukey alpha=0.05、四阶 3–30 Hz Butterworth 前后向滤波。
3. 对完整读取阵列计算中位数共模，按 DASQt 投影公式去除，再选目标道。输出 float32 MAT 波形。
4. MATLAB 转 double；EDWav 在 6–30 Hz 计算逐道片段指标，以逐道 `log(proxy)` 的
   `median + 2×MAD` 筛选。拒绝道置零，不加入有效道的 PSD 均值。
5. 每个 600 s 片段单独调用 `mCCFJ.correlate`，CL=600×Fs、OL=0、FL=CL、FD=1。
   同一窗口内以有效道的平均功率谱归一化互谱：

   `Cij(f) = conj(Xi(f))*Xj(f) / (mean_valid_k(|Xk(f)|²) + epsilon)`，
   其中 `epsilon = 1e-6 * mean_f(mean_valid_k(|Xk(f)|²))`，频率范围由 mCCFJ 的 FM 决定。

6. 对每个道对按其有效窗数线性平均；保存 `count_sum`。不加 OneBit、逐道白化或相位加权叠加。
7. CCF 缓存保存至 FM；补零恢复时域后，距离分箱、去掉零距列、速度滤波、正负时延对称平均和双边 mute。
8. H2 F-J 保留 `abs(real(FJ.dsp))`，不逐频率归一化；综合谱是有效日期原始 F-J 幅值的逐点平均。
9. 人工 polygon 建立综合 mask，按各日 ridge 速度偏移调整，再 F-J 反变换和 J0 衰减拟合。

显示中的色标裁剪不改变观测。原项目另有无 mute、1–15 Hz QC 预览；其设置与这里正式的
6–30 Hz 主流程不同。部署包当前保留正式主流程，未把那些辅助 QC 脚本混入入口。

## 配置和阶段

`matlab/workflow_config.m` 是全部默认值的来源；JSON 可覆盖已知字段，拼错或未知字段会报错。
部署默认将 EDWav 并行数从原机器的 32 降为 4，便于普通服务器运行；不改变计算公式。

| stage | 完成到哪里 |
| --- | --- |
| edwav | 预处理、筛选和记录预览 |
| ccf | 加上逐日期互相关缓存及 gather 图 |
| preview | 加上逐日期与综合 F-J，随后停止 |
| pick | 在交互 MATLAB 中选 polygon，然后提取衰减 |
| attenuation | 读取已有 polygon 并提取衰减 |

原主控中首次继续时关闭人工拾取的提示已修正：首次须用 `pick`，已有 mask 后才用 `attenuation`。
`mCCFJ.inversion` 在这里指 F-J 反变换，不是 Vs/Q/含水率反演。

## 缓存与可追溯性

每个预处理片段的 JSON sidecar 记录配置、数据文件路径/大小/修改时间、后端和预处理入口源码的
组合指纹，并校验 MAT 的大小和修改时间。修改后的文件不会仅凭同名被复用；中断后缺少 sidecar 的
片段会重新生成。源文件不做全文件校验和，避免每次扫描大体积原始数据；若修改数据同时保留大小和
修改时间，必须显式使用 `dasqt_rebuild_cache=true`。

CCF 缓存保留原设置比较，并加入预处理片段的大小和修改时间。缓存和结果中保留有效窗数、几何、
频率、波形处理参数、人工 mask 及日期。每次启动另存 `run_config_*.json`。

迁移得到的是相同算法和参数；不同 MATLAB/数值库/CPU 下浮点结果可能有舍入差异。
本次打包不等同于完成原始 24 h 重算、全链路跨机比较或最终衰减验证。
