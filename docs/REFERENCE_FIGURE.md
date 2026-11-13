# San Jose 500 道参考图参数

本文记录指定参考图
`outputs/sjdas_dasqt_mccfjflow2manual_500ch/ccf_24h_500ch_no_mute_0_3s_fj_1_15_qc.png`
的生成参数。参数来自独立绘图脚本 `plot_sjdas_ccf_fj_preview_nomute.m`、其读取的
24 h CCF cache、DASQt manifest 和对应 MAT 结果。参考图由已经生成的 cache 派生；图的
1–15 Hz F-J 设置不能与主控脚本中用于 cache / 其他流程的参数混为一套。

## 数据与预处理

| 参数 | 本图取值 | 含义 |
| --- | --- | --- |
| 数据日期 | 2023-09-20 00:00–24:00 | 使用 San Jose BlossomHill 记录的首个完整 24 h。 |
| 原始文件 | 12 个连续的 2 h HDF5 文件 | manifest 记录文件间无时间缺口；按时间排序后切成完整片段。 |
| 输入记录 | `Acquisition/Raw[0]/RawData` | HDF5 排列为时间 × 道；此批输入覆盖物理道 16700–17199。 |
| `raw_channel_first0` | 0 | HDF5 数据集内从 0 开始的目标道列索引；本数据集本身就是物理道 16700–17199。 |
| `Fs` | 200 Hz | 每秒 200 个采样点，采样间隔 0.005 s。 |
| `segment_seconds` | 600 s | 按完整连续 600 s 片段处理；一天共 144 段。 |
| 每段样本数 `N` | 120000 | `N=Fs*segment_seconds`，输入矩阵逻辑尺寸为 `[120000,500]`（时间 × 道）。 |
| 波形精度 | DASQt cache 为 `float32`；MATLAB 相关前转 `double` | 记录缓存的数据类型和 MATLAB 算法实际输入类型。 |
| 片段选择 | `max_segments=144`，`selected_dates=[]` | 取排序后最多 144 个完整片段；空日期列表表示自动采用全部缓存日期。 |
| 日期有效门槛 | `minimum_segments_per_window=72` | 至少有 72 个 600 s 片段且存在可用道对才纳入日期；72 段等于 12 h。 |
| 并行数 | CCF 日期并行 `n_workers=4`；EDWav 并行 `edwav_workers=32` | 运行资源设置，不改变处理公式或输出定义。 |
| 道数 | 500 | 对应物理道 16700–17199。 |
| `station_x` | `0:499` m | 目标阵列内的位置坐标；参考道到各道偏移为 0–499 m。 |
| 道间距 | 1 m | 相邻 DAS 道中心间距。 |
| gauge length | 10 m | 传感空间平均尺度，不是道间距。 |
| DASQt 操作顺序 | 去均值 → 去线性趋势 → Tukey taper → bandpass → 共模去除 | 在 MATLAB 相关前完成；结果缓存为每段波形。 |
| DASQt taper | Tukey `alpha=0.05` | 预处理边缘渐消比例。 |
| DASQt bandpass | 3–30 Hz，Butterworth 4 阶，zero-phase | 预处理波形频带；`detrend=false`、`taper=false` 是滤波器内部选项，因为对应操作已在前面完成。 |
| 共模去除 | 开启；对读取的 500 道共同处理 | 由完整 500 道估计共模并按 DASQt 投影步骤去除。 |
| DASQt whitening | 关闭 | 不做 DASQt 时间/频率白化；后续 CCF 使用 mCCFJ 的 PSD 归一化。 |
| EDWav 频带 | 6–30 Hz | 用于逐道、逐个 600 s 段的筛选指标。 |
| EDWav `FR` | 240 | 频带划分参数，不是 240 Hz。 |
| EDWav `NT` | 1 | sinusoidal taper 数，不是噪声类型选择。 |
| EDWav `SF` | 0.05 | 平滑比例。 |
| EDWav `NW` / `DW` | 60 / 60 | 滑动评估窗含 60 个小窗，步长 60 个小窗；在本设置下小窗约 10 s，因此评估覆盖 600 s。 |
| EDWav 小窗长度 | 2000 点，即 10 s | `ceil(240*200/(30-6))`；这解释了 `NW=60` 为什么覆盖 600 s。 |
| EDWav 指标与阈值 | 保存 `result(1)`；逐道 `log(proxy) <= median + 2*MAD` | 对每一道跨 144 段计算阈值；拒绝段不参与该窗 PSD 均值。此数据实际 61828/72000 道段通过，参考道通过 124/144 段。 |

## 互相关与 CCF gather

| 参数 | 本图取值 | 含义 |
| --- | --- | --- |
| 参考道 | 局部索引 1，即物理道 16700 | 构造参考道到全部 500 道的 gather；不是 500 × 500 全道对。 |
| `RR` 道对数 | 500 | 包括参考道自相关，偏移从 0 到 499 m；cache 中每个道对保留自己的有效段计数。 |
| `CL` | 120000 点（600 s） | 单次相关调用完整使用一个 600 s 输入片段。 |
| `OL` | 0 点 | 相邻相关窗无重叠；由于 `CL=N`，每个片段只产生一个相关窗。 |
| `FL` | 0，函数内设为 `CL=120000` | FFT 长度等于相关窗长度；没有补零到 `2N-1`，因此保留 mCCFJ 当前的 FFT 周期相关定义。 |
| 时间归一化 `NT` | `No` | 不做 one-bit。 |
| 频率归一化 `NF` | `PSD` | 互谱按当前 600 s 窗有效道的平均功率谱归一化；不是标准 Welch 每 Hz PSD，也不是逐道或逐对归一化。 |
| PSD 计算定义 | `Cij(f)=conj(Xi(f))*Xj(f)/(q(f)+epsilon)` | `X=fft(wave,N,1)/N`；`q(f)=mean_active_k(abs(Xk(f))^2)`，`epsilon=1e-6*mean_f(q(f))`。`active` 是该窗频带内有正功率的有效道，参考道也计入。 |
| taper `TP` | `No` | mCCFJ 相关阶段不另加 taper；DASQt 前处理已施加 Tukey taper。 |
| 最大 CCF 频率 `FM` | 30 Hz | cache 保存到 30 Hz；实际最后一个保存频点约 29.9983 Hz，频率间隔约 0.0016667 Hz。 |
| 频率抽取 `FD` | 1 | 不抽取频率点，避免恢复时域 CCF 时引入额外时域混叠。 |
| GPU | `No` | CCF 使用 CPU。 |
| 日期内叠加 | 按道对的 `cstack` 计数加权平均 | 不同道对有效段数不同；此 cache 的 `count_sum` 为 106–124，中位数 116。 |
| 距离分箱 `distance_bin_m` | 0.8 m | 通过 `mCCFJ.stack_bin` 整理距离；由于偏移为 1 m 整数间隔，此结果仍为 500 个偏移列，0–499 m。 |
| 速度 / 波数滤波 | `[50,1000]` m/s | 使用 `mCCFJ.filtering` 按偏移和速度界限在 CCF 频谱上做波数滤波；这不是 3–30 Hz 的时间域 bandpass。 |
| 零偏移列 | gather 保留；F-J 排除 | 0 m 自相关留在 CCF 图中且不经过按非零偏移定义的滤波；进入 F-J 前删除。 |
| 正负支处理 | `h(t,r)=0.5*(C(+t,r)+C(-t,r))`，`t>=0` | 图中不是单独选原始正支；正负时间对应平均形成半支。0 s 只计一次。 |
| GW mute | 关闭 | 本图跳过 `GW_mute/GW_mute1`。速度 / 波数滤波仍然应用，因此“no mute”不代表没有滤波。主控中的 `top_mute`、`bottom_mute` 在本图未使用。 |
| CCF gather 内存轴 | `ccf_gather[59999,500]`、`time_positive=0:0.005:299.99 s` | MAT 文件保存完整正时延半支镜像前的 gather；PNG 的上方 CCF 面板再裁出 0–3 s。 |
| 零偏移图例文字 | 图上标注“all 500 offsets are nonzero” | 这句标题与数据不符：实际 500 列包含 0 m 自相关，范围是 0–499 m；0 m 列在两张 CCF 图中保留且没有做速度滤波。 |

## F-J 频散谱

| 参数 | 本图取值 | 含义 |
| --- | --- | --- |
| F-J 频率范围 | `[1,15]` Hz | 交给 `mCCFJ.transform` 的频率上下限；不是 CCF cache 的 `FM`。 |
| F-J 输入频率步长 | 0.1 Hz | 从约 0.0016667 Hz 的 CCF 频率轴按 `stride=round(0.1/df)=60` 抽取。 |
| 实际 F-J 频率轴 | 1.0–14.9 Hz，共 140 点 | 15 Hz 是图轴显示上限，变换结果最后一个频点为 14.9 Hz。 |
| 速度轴 | `100:800` m/s，共 701 点 | `mCCFJ.transform` 计算的试探相速度。 |
| transform 输入 | `[频率,距离]` 复数频谱和非零偏移 | 由完整半支重建对称记录后 FFT 得到；不受 CCF 图的 0–3 s 显示裁剪影响。 |
| `Fun` | `H2` | mCCFJ 的 H2 频率–Bessel 变换；输出为复数 `FJ.dsp[701,140]`。 |
| `Win` | `No` | 不加空间窗；显式覆盖 mCCFJ 的默认 `Hamming_1`。 |
| 输出显示量 | `abs(real(FJ.dsp))` | 使用复变换实部的绝对值；不取复数模、不平方、不做逐频率归一化。 |
| GPU / `Num` | `GPU='No'`、`Num=0` | transform 在 CPU 串行执行。 |
| ridge 种子与范围 | 10 Hz；140–450 m/s | 仅用于图上黑色引导线。当前预览脚本用相邻频率列局部最大值追踪（速度索引约 ±40），不是主流程的 `findpeaks` 趋势追踪；不要把该线当作正式 ridge 验收结果。 |

## 图形显示参数

| 参数 | 本图取值 | 含义 |
| --- | --- | --- |
| CCF 时间范围 | 正时延 0–3 s，共 601 点 | 仅用于上方 CCF 两面板显示；不是相关输入窗，也不是 F-J 输入截窗。CCF 数据未置零。 |
| CCF 上方面板 | 非零偏移经速度滤波、零偏移原样保留，再做正负支对应平均 | 每列使用原始 CCF 幅值；对称色限取该显示矩阵绝对值的第 99 百分位，实测约 `9.27078e6`。 |
| CCF 中方面板 | 每列除以本列 0–3 s RMS | 仅供显示 QC；不送入 F-J。对称色限取归一化矩阵绝对值第 99 百分位，实测约 3.31036。 |
| 频散图色限 | `[0, prctile(spectrum(:),99.5)]` | 仅改变颜色映射，不缩放谱数据；本图上限约 `4.16124e12`。 |
| CCF colormap / 方向 | 自定义红–白–蓝；offset 横轴，时间纵轴向下增加 | 参考道偏移 0–499 m；CCF 图 `YDir='reverse'`。 |
| F-J colormap / 轴范围 | `jet`；1–15 Hz、100–800 m/s | F-J 图用 `axis xy`；白色虚线只标 12 Hz（可靠范围配置为 3–12 Hz）。 |
| 图窗与导出 | `Position=[60,40,1450,1220]`；300 dpi | MATLAB `exportgraphics`；当前 PNG 栅格为 5905 × 4841，实际尺寸会受 MATLAB 图形环境影响。 |

本图的处理顺序是：完整 600 s 片段相关与日期叠加 → 距离分箱 → 非零偏移速度滤波 → 正负支对应平均 →
用完整半支重建对称记录并做 H2 F-J → 仅将 CCF gather 裁至 0–3 s 作图。不要把绘图裁剪、逐道 RMS
显示归一化或颜色限幅当作互相关 / F-J 的科学处理参数。
