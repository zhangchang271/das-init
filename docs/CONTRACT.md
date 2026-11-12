# 数据与计算约定

本文定义 **das-init 当前已确认的 San Jose CCF → F-J 流程**。迁移程序应同时复现数据含义、
数组接口和数值结果，不能只复现步骤名称。代码依据为
[run_pipeline.m](../matlab/run_pipeline.m)、[mCCFJ.m](../vendor/matlab/mCCFJ.m)、
[EDWav.m](../vendor/matlab/EDWav.m) 和 [prepare_dasqt.py](../python/prepare_dasqt.py)。
默认参数由 [workflow_config.m](../matlab/workflow_config.m) 定义；
[demo_small.json](../configs/demo_small.json) 是便于验收的 50 道实例。
这份约定描述已验证行为，不把相关函数当作校准过的格林函数，也不把频散 ridge 当作 Vs 模型。

## 1. 每一步提取什么

| 阶段 | 从数据提取 / 保留的信息 | 输出物理含义 | 给下一步什么 |
| --- | --- | --- | --- |
| 原始记录与几何 | 连续采样、道序、时间、空间位置 | 仪器记录的 DAS 波形；本程序没有做应变 / 应变率物理单位标定 | 同时段的多道波形与位置 |
| DASQt | 固定频带内的波动，去除趋势与全阵列共模投影 | 处理后的仪器波形，已改变振幅与空间共模信息 | 同一预处理历史的 `wave` |
| EDWav | 每一道段的波场弥散性相关统计指标 | 用于相对筛选的经验指标；不是速度、能量或噪声方差 | `keep(segment,channel)`，决定哪些道段进入相关 |
| PSD 互相关 | 参考道与接收道的相干传播信息 | 以当前窗有效阵列平均功率谱归一化的互谱；时域有正、负时间两支 | 复数频域 CCF、道对与有效窗数 |
| 日期叠加 | 多个有效 600 s 窗中稳定的相关成分 | 各道对自己的有效窗平均，观察时长可以不等 | 未分箱、未速度滤波、未折叠的 CCF cache |
| 分箱 / 速度滤波 | 距离相近的相关信息、速度范围内的传播成分 | 沿距离组织的 CCF；振幅受明确的分箱与滤波影响 | 递增非零偏移上的双支 CCF |
| 正负支折叠 | 正、负时间对应位置的对称成分 | 半支 `h(t,r)=[C(t,r)+C(-t,r)]/2, t>=0`；方向不对称信息被舍弃 | 半支数据，必要时在这里 mute，再恢复对称频谱 |
| H2 F-J | 不同频率下、与试探相速度一致的距离相干性 | 复数频散像 `FJ.dsp(c,f)`；当前展示量是 `abs(real(FJ.dsp))` | 相速度—频率谱，不是功率谱或概率 |
| 日期综合 / ridge | 各日共有的谱结构与沿频率连续的局部峰 | 有效日期幅值谱的等权平均及 `c(f)` 观测 | 后续人工模式选择的依据；尚不是反演结果 |

## 2. 轴、索引、单位

以下尺寸均为 **MATLAB 中 `size()` 看到的逻辑尺寸**。

| 符号 | 含义 | demo |
| --- | --- | --- |
| `N` | 每段采样点数，`Fs * segment_seconds` | 120000 |
| `M` | 目标道数 | 50 |
| `L` | FFT 点数，`FL=0` 时取 `N` | 120000 |
| `Kcorr` | `correlate` 的完整非负频率点数，偶数 `L` 时 `L/2+1` | 60001 |
| `Kwork` | 主流程从 cache 重建频率轴的实际点数，见第 6 节 | 60000 |
| `B` | cache 实际保留的频率点数，以保存的 `freq` 为准 | 18000 |
| `P` | 原始参考道对数，含自相关时为 `M` | 50 |
| `R` | 分箱后进入 F-J 的非零距离数 | 49 |
| `V, F, D, S` | 速度点、最终频率点、有效日期、片段数 | 701、120、1、1 |

时间为秒、频率为 Hz、位置 / 道间距 / gauge length 为 m、相速度为 m/s。
10 m gauge length 是传感空间平均尺度，不能替代 1 m 道间距。
`raw_channel_first0` 是 HDF5 内从 0 开始的列索引；`reference_channel`、`RR` 道号是目标阵列内
从 1 开始的索引。demo 目标物理道号为 16700–16749，参考道局部索引为 1。
相关时间是两道相对时间；原始 `start_time` 是片段绝对时间。源数据未声明时区，本程序不擅自转换。

`wave`、CCF 的列是道 / 道对 / 距离；F-J 的行是速度、列是频率。
MAT v7.3 是 HDF5，直接用 h5py 看到的维序与 MATLAB 可能相反，而且复数可能是 `real/imag`
复合类型、cell 是对象引用。不要把磁盘上的 shape 直接当作本文逻辑维度。
demo 的 `result.mat` 和 `checkpoints.mat` 使用普通 MAT v7，便于 MATLAB / SciPy 读取；
坐标和计数允许使用紧凑整数存储，比较前转为数值，不能据磁盘整数类型判断物理量的精度。

## 3. 原始输入与 DASQt 接口

HDF5 数据集 `Acquisition/Raw[0]/RawData` 为 `[时间,完整读取道]`。
需要采样率、片段起始时间、道号及完整 600 s 样本；不跨缺口拼成一个假连续窗。
当前读取器依赖 BlossomHill 文件名和根属性，其他仪器须显式适配。

`dasqt_preprocess_full(raw_time_channel, cfg, backend)`：

`cfg` 在此函数中实际读取 `fs_hz`（标量 Hz）、`band_hz`（两个 Hz 边界）、
`butter_order`（标量阶数）、`tukey_alpha`（标量比例）和 `common_mode_removal`（布尔值）。
`backend` 是按顺序包含 `demeaning, detrending, cosine_taper, bandpass, common_mode_noise_removal`
五个函数的 tuple，来自仓库固定的 DASQt 后端。

| 输入 / 输出 | 尺寸 | 约定 |
| --- | --- | --- |
| `raw_time_channel` | `N × Mfull` | 原始完整预处理孔径，demo 为 500 道 |
| 内部 `work` | `Mfull × N` | float32；沿每道时间去均值、去线性趋势、Tukey 0.05、四阶 3–30 Hz 前后向滤波 |
| 共模 | `1 × N` | 每时刻全孔径中位数 `m(t)`；逐道减去 `sum(x*m)/sum(m*m)*m`，不是直接减中位数 |
| 返回值 | `N × Mfull` | float32，完成全部处理后才截取目标 50 道 |
| 缓存 `wave` | `N × M` | float32；MATLAB 后续转 double，不重新做 DASQt |
| `raw_valid` | `1 × M` | 原始目标道全样本有限，且绝对值第 95 百分位大于 0 |
| 元数据 | 标量 / 字符串 | `fs_hz`、`start_time`、道间距、gauge、目标及完整孔径、来源位置 |

非有限样本在预处理内替换为 0，同时对应目标道的 `raw_valid=false`；该标记必须传递到筛选，
不能只处理波形后丢弃有效性信息。仅拿原始 50 道重新算共模，不能复现“500 道处理后取 50 道”。
随仓库分发的缓存已经处理好，验收从 EDWav 开始，不再叠加一次滤波或共模处理。

## 4. EDWav：筛选接口不等于波形变换

主流程调用 `EDWav.evaluate_sliding(wave(:,ich),Fs,'FB',[6 30],'FR',240, ...
'NT',1,'SF',0.05,'NW',60,'DW',60)`，返回逐样本指标列 `result` 及 `infos`。
当前主流程**只保存 `result(1)`** 为该道该 600 s 段的 `proxy`；不是对返回列求平均。

函数的 `wave(:,ich)` 必须是 double `[N,1]` 单道列向量，`Fs` 是标量 Hz；
`result` 和 `infos.stack` 为 `[num_of_win*len_of_win,1]`，本 demo 均为 `[120000,1]`。
`infos` 还含实际 `len_of_win`（点）、`num_of_win / num_of_sld / NW / DW`（个数）、
`freqs`（频率轴）及 `SE`（覆盖样本范围）。尾部不足小窗的样本可能不在返回列中；
无有效评估叠加时可能出现非有限指标，主流程由 `eligible` 拒绝，不能把它当作有效零指标。

容易误读的旧字段名必须按实际接口理解：

| 配置字段 | 实际函数参数 | 实际含义 |
| --- | --- | --- |
| `edwav_frequency_resolution=240` | `FR` | 频带划分的最小份数，不是 240 Hz |
| `edwav_noise_type=1` | `NT` | sinusoidal taper 数，不是噪声类型开关 |
| `edwav_window_seconds=60` | `NW` | 每个滑动评估窗含 60 个小窗，不是 60 s |
| `edwav_distance_seconds=60` | `DW` | 滑动间隔 60 个小窗，不是距离，也不是直接的秒数 |

当前小窗长度 `ceil(240*200/(30-6))=2000` 点，即 10 s；60 个小窗正好覆盖 600 s。
不能因为字段名带 seconds，在重写时把这里的评估窗缩成 60 s。

`proxy / raw_valid / eligible / keep` 均为 `[S,M]`。
`eligible=raw_valid & isfinite(proxy) & proxy>0`；在每道上跨片段计算
`log(proxy)` 的中位数及**未乘 1.4826 的 MAD**，保留 `log(proxy)<=median+2*MAD`。
单段 demo 的 MAD 为 0、50 道全保留，不能验证多片段筛选的统计稳定性。
输出 `keep` 不包含速度信息；下一步仅将拒绝道波形标成不参与相关，不改变通过道的幅值。

## 5. PSD-CCF：频谱定义与计数

```matlab
CC = mCCFJ.correlate(wave, [station_x;zeros(1,M)], Fs, ...
    'AX','xyz','CL',N,'OL',0,'FL',0,'NT','No','NF','PSD', ...
    'FM',30,'FD',1,'TP','No','RR',RR,'GPU','No');
```

`wave` 为 double `[N,M]`；`station_x` 为 `[1,M]`，单位 m。
`CL/OL/FL` 的单位是采样点，不能把 `CL=600` 当作 600 s。
`TP='No'` 表示相关阶段不另加 taper；DASQt 的 Tukey 已经做过。
`RR` 为 `[P,6]` cell，每行是 `[距离m,参考道索引,接收道索引,方位角,参考名称,接收名称]`。
当前显式构造参考道 1 到全部目标道，含 0 m 自相关；不能省略 `RR` 后使用函数的全道对默认值。

每个窗中非零样本不足一半的道被拒绝；有效道至多一个则整个窗跳过。
频谱计算为 `X=fft(wave,L,1)/L`，取非负频率，内部点 `X(2:end-1,:)*=2`，再选 `f<=FM`。
本实现名为 PSD 归一化，但不是直接调用 Welch 得到标准每 Hz 功率谱密度：

```text
q(f)      = mean_active_k |Xk(f)|²
epsilon   = 1e-6 * mean_f q(f)
Cij(f)    = conj(Xi(f)) * Xj(f) / (q(f) + epsilon)
```

`active` 是当前窗选定频段内有正功率的全部有效道，包含有效参考道；
分母不是 `|Xi|*|Xj|`，也不是每对单独求 PSD。`epsilon` 的平均频带跟 `FM` 一起变化。
交换道对会共轭互谱并交换时间两支。按当前 `conj(Xi)*Xj` 约定，接收道相对参考道晚到的
理想脉冲出现在正时间。频域量的仪器单位在该比值中抵消，绝对传播振幅已不能直接还原。

| `correlate` 输出 | 尺寸 | 含义 |
| --- | --- | --- |
| `CC.ccf` | `Kcorr × P` complex double | 平均互谱；`FM` 以上补 0 |
| `CC.freq` | `Kcorr × 1` | 非负频率，间隔 `Fs/L` |
| `CC.cct` | `L × P` real | 底层自定义 IFFT 得到的双支相关，缩放见第 6 节 |
| `CC.time` | `1 × L` | 偶数 `L` 时 `[-L/2,...,L/2-1]/Fs` |
| `CC.ccr` | `P × 6` cell | 与 `ccf` 列一一对应的道对 |
| `CC.info.cstack` | `1 × P` | 每对真正有非零互谱的有效窗数；不是统一总窗数 |
| `CC.acf / info.astack` | `Kcorr × M / 1 × M` | 自功率谱及各道有效窗数；主流程不把它们写入日期 CCF cache |

日期 cache 将每段平均互谱按该段的 `cstack` 加权，再除以每对累计的 `count_sum`。
零计数对保存为 0。存储字段为 `ccf[B,P]`、`freq[B,1]`、`ccr[P,6]`、
`count_sum[1,P]`、`info`、`cache_config`，位置在分箱、速度滤波和折叠之前。
demo 实际 `B=18000`、频率 0–29.998333333333335 Hz：浮点比较 `f<=30` 恰好排除了 30 Hz。
须读取实际轴；不要凭 `FM/df+1` 猜数组长度、补一个不存在的 cache 点。

`ccf_24h_*.mat` 是沿用的日期分组文件名，不保证恰有 24 h 数据。
demo 是一个 600 s 窗；50 对的 `count_sum` 各为 1，`sum(count_sum)=50`，不是 50 个时间窗。
多日综合时 `pair_window_count` 是每日期道对窗数之和，主要用于有效性记录，不是 F-J 日期平均的权重。

## 6. 分箱、时域缩放与速度滤波

`correlate` 原生时域轴为 −300 到 299.995 s。主流程读取 cache 后，以
`df=median(diff(freq)); freq_full=(0:df:Fs/2).'` 构造重建频率轴，再补频谱、恢复双支时域轴。
**当前参考运行存在端点一致性限制**：`df=0.0016666666666669272` 的舍入使重建轴实际为
60000 点，末频率约 99.99833333334897 Hz，不是理论的 60001 点 / 100 Hz。
普通 Hermitian IFFT 此时给出 119998 点，构造的时间轴为 −299.995 到 299.990 s。
底层 `stack_bin/filtering` 又以 `NL=1+Kwork` 的奇偶分支恢复出 119999 点，
却继续保留此前 119998 点的 `CC.time`；折叠按该时间轴的索引进行，因此两个最外端点不参与半支。
这不是一个严格一致的 FFT 时间—频率网格。此文记录其实际行为以复现已确认结果，
**没有把这个端点问题视为已修正**；统一频率 / 时间网格需要另行修改并重验参考结果。
不能在迁移时擅自补回理论点数后仍声称与当前基准逐点等价。
`FL=L=N` 且未为线性相关补至 `2*N-1`，因此这里是 FFT 周期相关；直接换成线性 `xcorr`
会改变长度、端点和数值。

`mCCFJ.stack_bin(CC,0.8)` 对距离分箱；箱中心从最小距离起每 0.8 m 一个，边界为中心 ±0.4 m，
用唯一箱编号分配道对。各频率将**精确为 0 的谱点当成 NaN 后等权求均值**，不是按
`count_sum` 再加权；距离取箱内距离均值。空箱删除，输出 `ccr` 变成 `[Rbin,1]` 数值距离，
原始道对映射仍在 cache。当前 1 m 道间距没有合并不同距离；demo 得到 0–49 m 共 50 列。
一般多道对分箱的贡献数并未单独保存，不能假定这里具备完整的分箱振幅统计。

这两个函数均返回更新后的 `CC` struct，调用者必须接收返回值：

| 接口 | 读入 | 更新后的主要字段 |
| --- | --- | --- |
| `CC=mCCFJ.stack_bin(CC,width)` | `ccf[Kwork,P]`、`freq[Kwork,1]`、`ccr[P,6]` cell 或数值距离；`width` 为标量 m | `ccf[Kwork,Rbin]`、`ccr[Rbin,1]` 数值距离、重新生成的 `cct`；不重建 `time` |
| `CC=mCCFJ.filtering(CC,vbound)` | `ccf[Kwork,R]`、`freq[Kwork,1]`、`ccr[R,1]`；`vbound=[vmin vmax]`，m/s | 同尺寸的滤后 `ccf`、重新生成的 `cct`；`freq/ccr/time` 沿用输入 |

当前两函数的 `cct` 行数与 `time` 长度不一致，见本节开头；不能只检查 `ccf` 维度就忽略此限制。

底层 `myifft_cc(Uf,NL)` 实际调用 `ifft(Ufull * size(Uf,1)^2,[],1,'symmetric')`，再由调用方 `fftshift`。
`stack_bin` 和 `filtering` 都据频谱重新生成 `cct`，所以进入折叠 / 预览的时域 CCF 带有
`Kwork^2=60000^2` 的固定幅值因子。主流程最初补齐频谱时使用普通 IFFT，随后被上述结果覆盖。
迁移时只用普通 IFFT 会让谱形可能相似而 CCF / F-J 幅值不一致；不能用逐道归一化掩盖差异。
该因子不是物理增益标定，也不是每经过一个步骤再累乘一次。

移除 0 m 列后调用 `mCCFJ.filtering(CC,[50 1000])`。
它沿每个距离的**频率轴**对复谱实部 / 虚部分别做二阶 Butterworth `filtfilt`：
低通截止 `r/vmin/(1/df/2)`，再高通截止 `r/vmax/(1/df/2)`。
这是当前函数实现的速度选择，不能替换为普通 3–30 Hz 波形带通。
0 m 自相关只留在 CCF 展示，未送入该滤波或 H2 F-J。demo F-J 输入距离为 1–49 m。

## 7. 正负两支与“半支”必须说清楚

原始两支表示参考道与接收道的两种相对时间关系，可能振幅不等；噪声源方向、介质及处理都会
影响它们。仅凭正负号不能断言已提取某一个真实震源的单向格林函数。
当前流程用的是**正负支对应平均后的半支**，并不是只选原始正支：

```matlab
positive = find(CC.time>=0);
negative = find(CC.time<=0);
negative = negative(2:end);             % 去掉时间轴最左端；具体端点见第 6 节
h = 0.5*(CC.cct(positive,:) + flipud(CC.cct(negative,:)));
% 当前 demo: h 为 59999 × 49；t_half 为 0:0.005:299.990 s
```

例如同一距离按时间 `[-2,-1,0,1,2]` 记录 `[2,4,10,8,6]`，则半支 `[10,6,4]`；
原始正支 `[10,8,6]` 不相同。零时刻只保留一次，不翻倍。不能把全双支当成两组独立距离样本。
这个示例解释对应关系；实际偶数轴还需处理最左端没有正端点对应的一个样本。

默认 `apply_gw_mute=false`。启用时，`GW_mute/GW_mute1` 的输入是 `h[时间,距离]`，
`dt` 为秒、`r` 为 m 的行向量、时间参数先换成采样点。`top_mute/bottom_mute=[速度m/s,时间偏移s,平滑除数]`；
`reference_n=round(mute_reference_s/dt)`，`T1=round(reference_n/平滑除数)`，
`T0=round(时间偏移/dt)`，接收 `r=offset.'` 和同长全 0 参考位置。mute 改变参与 F-J 的半支波形。
随后主流程按下式恢复偶数长度的对称记录，再 FFT：

```matlab
cct_sym = [zeros(1,size(h,2)); flipud(h(2:end,:)); h];
ccf_sym = fft(ifftshift(cct_sym,1),[],1);
ccf_sym = ccf_sym(1:Kwork,:);
```

这里最前面 1 行是负时间最外端点的重建约定（当前 demo 为 −299.995 s），**不是 ±1 s 窗口外置零**。
科学处理保留完整半支；`ccf_window_half_s=1` 仅裁出最后保存 / 展示的 ±1 s 窗口，
不缩短 600 s 输入相关窗，不截断 F-J 的半支输入。

F-J 入口本身要求的是 `[频率,距离]` 复谱，不能把 `[时间,距离]` 的半支直接传给
`mCCFJ.transform`。正确交接是：双支 → 对应平均半支 → 可选 mute → 对称重建 → FFT → F-J。

## 8. F-J 接口、幅值与 ridge

先按 `stride=round(0.1/df)=60` 从 0 Hz 起抽频，选至配置上限；**不是把波形采样率改为 10 Hz**。
`mCCFJ.transform(CC,c_range,[fmin fmax],'Fun','H2','Win','No','GPU','No','Num',0)`
实际读取以下字段：

| 变量 | 尺寸 | 含义 |
| --- | --- | --- |
| `CC.ccf` | `Finput × R` complex | 上述折叠 / 重建后的频谱，列对应递增非零距离 |
| `CC.freq` | `Finput × 1` | 对应频率；函数内再选频带 |
| `CC.ccr` | `R × 1` 数值或 cell 首列 | 距离 m，决定积分权重和波数核 |
| `c_range` | 向量，函数内转成行 | `100:800` m/s，主配置保存为列 |
| `FJ.dsp` | `V × Fnative` complex | 速度—频率变换结果 |
| `FJ.frq / FJ.vel` | `Fnative × 1 / 1 × V` | 原生频率轴 / 速度轴 |

H2 实现先对 `real(CC.ccf)` 调 `hilbert`，MATLAB 默认沿第 1 维，**这里是频率维**。
在每个频率上以 `k=2*pi*f/c`、`J0(kr)-i*Y0(kr)` 为核，对距离积分
`trapz(r, r .* Gfs(f,r) .* H2(kr))`。保留其实际轴与 `r dr` 权重，不能仅凭“H2”名称
换成另一个 Hilbert 轴或积分公式。当前 `Win='No'` 显式覆盖底层 `Hamming_1` 默认值。

主流程取 `abs(real(FJ.dsp))`，不是 `abs(FJ.dsp)`、复谱模平方或逐频率最大值归一化。
再线性插值到统一输出轴：demo 为 `3:0.1:14.9` Hz、`100:800` m/s。
仅因浮点舍入越界的端点允许小容差吸附，不外推缺失频带。
每日谱先存 single，跨有效日期逐点等权平均，再转 double；这一步的精度也是结果的一部分。
原生 FFT / 边界浮点比较可能令 15 Hz 未进入变换，必须对照实际轴。

ridge 在 140–450 m/s 内，从最接近 10 Hz 的种子列最大值起，向两侧用 `findpeaks`
找局部峰；预测索引为 `2*previous-previous_previous`，选离预测最近的峰，同距时选幅值较高者，
无局部峰才退回范围内最大值。不是每列直接 `argmax`，也不是固定宽度搜索窗。
先得到各日 ridge；综合 ridge 对综合谱重新追踪，不对每日 ridge 取平均。
`c(f)` 是当前选定谱结构的相速度观测；自动追踪没有独立证明它全频段属于基阶模式。

## 9. 最终文件接口与验收

| 文件 / 字段 | demo 逻辑尺寸 | 说明 |
| --- | --- | --- |
| `ccf_preview_50ch.mat: ccf_gather` | `401 × 50` | 速度滤波后折叠半支镜像回双侧，再裁出 ±1 s；0 m 列未做速度滤波 |
| `ccf_time_s / offset_all` | `401 × 1 / 50 × 1` | −1 到 +1 s、0 到 49 m |
| `spectrum / frequency / velocity` | `701 × 120 / 120 × 1 / 701 × 1` | 综合 `abs(real(FJ.dsp))` 及坐标 |
| `ridge_velocity` | `120 × 1` | 综合谱的趋势追踪速度，m/s |
| `count_sum` | `1 × 50` | 展示所取的第一个日期的原始道对有效窗数 |
| `mccfj_composite_50ch.mat: daily_spectrum` | `701 × 120 × D` | MATLAB 省略尾部单例维；single |
| `daily_ridge_velocity / pair_window_count` | `120 × D / D × 1` | 每日 ridge / 每日道对窗数和 |
| `composite_spectrum / composite_ridge_velocity` | `701 × 120 / 120 × 1` | 综合结果 |
| `keep / raw_valid` | `S × 50` | 片段—道筛选；不是频率—道矩阵 |

多日图的 CCF 来自第一个有效日期，频散底图来自全部有效日期；不能把它理解成全部日期 CCF 的
统一展示。预览双侧是同一折叠半支的镜像，不能用该图评价原始两支的方向不对称性。
图中第二幅逐道 RMS 归一化只用于显示；第一幅“原始 CCF”指未做此显示归一化，已经过上述处理。
CCF 99% 色阶、谱 99.5% 色阶只是绘图裁色，不改变 MAT 数值、不参与 F-J。

迁移验收使用 [contract.json](demo/contract.json)、[checkpoints.mat](demo/checkpoints.mat)
和已确认的 [result.mat](demo/result.mat)。`checkpoints.mat` 提供 EDWav 指标 / mask、
原生频域 CCF 的选定行、原始频率行索引和道对，不重新实现算法来制造参照。
先比较输入、mask、计数、原生 CCF，再比较最终 CCF、频散谱幅值和 ridge，能定位差异从哪一步出现。

```bash
bash scripts/run.sh configs/demo_small.json preview
```

```matlab
addpath('scripts');
report = validate_demo;                      % 检查默认 demo 输出目录，中间和最终结果均比较
report = validate_demo('/path/to/output');    % 同一 demo 的另一个输出目录
report = validate_demo('/path/to/result.mat');% 其他程序导出的同字段结果，仅验收最终结果
```

MAT 文件模式至少需输出 `ccf_gather,ccf_time_s,offset_all,spectrum,frequency,velocity,`
`ridge_velocity,count_sum`，并严格遵守表中维序。验证不自动转置、归一化或拟合缩放。
默认谱 / 波形相对容差 `1e-5`，数值绝对容差 `1e-10`，坐标绝对容差 `1e-9`，ridge 绝对容差 `0.5 m/s`；
归一化谱即使颜色相似也不能通过幅值比较。容差针对同输入同算法的部署比较，不是统计误差条。
精确阈值及原生 CCF 基准尺寸保存在 JSON 中；失败会报字段与误差。

需要人为检查的仍包括传播走时、孔径支持的频带、模式归属，以及多窗口 / 多日收敛。
单个 demo 的通过只能说明这份输入和这些观测量复现；稀疏 CCF 检查也不是全数组证明。
当前不验收复数 F-J、人工 mask 或最终衰减，更不验收 Vs / Q / Sw 反演。

## 10. 主控交接与排查

`run_workflow(config_path,stage)` 是公开入口：两个输入均为字符串，配置由
`workflow_config` 补全为 struct，`run_pipeline(cfg)` 写文件而不返回计算数组。
以下局部函数在 `run_pipeline.m` 内，列出接口供迁移对应，不承诺可在外部直接调用。

| 局部接口 | 输入变量 | 返回内容 |
| --- | --- | --- |
| `build_24h_ccf(ids,file_paths,keep,p,cache_file)` | `ids` 为当前日期片段索引向量；`file_paths[S,1]` 为 MAT 路径 string；`keep[S,M]` 为逻辑 mask；`p` 为参数 struct；`cache_file` 为目标路径 | 标量逻辑 `ok`；写出第 5 节日期 cache |
| `compute_fj_from_ccf(cache_file,p)` | 未分箱的日期 cache 路径；`p` 含 `Fs`、分箱、速度滤波、折叠后的可选 mute、频率 / 速度轴、F-J 和 ridge 参数 | `FJ`、`spectrum[V,Fnative]`、`offset[R,1]`、`ridge_velocity[Fnative,1]`、标量 `pair_count_day=sum(count_sum)` |
| `dispersion_from_ccf(cache_file,p)` | 同上，另用 `p.frequency[F,1]` 作为统一输出轴 | `spectrum_day[V,F]`、`ridge_day[F,1]`、`pair_count_day`；只在频率轴插值 |
| `pickRidgeAlongTrend(spectrum,seed,first_velocity,last_velocity)` | `spectrum[V,F]`；后三者均为从 1 开始的数组索引，不是 Hz 或 m/s | `ridge[F,1]` 是速度行索引；需再用 `p.velocity(ridge)` 得到 m/s |
| `crop_ccf_window(gather,time_s,half_s)` | `gather[T,R]`；`time_s` 为长度 T 的秒坐标；`half_s` 为标量秒 | 保留 `abs(time_s)<=half_s` 的行，输出矩阵与列向量时间轴；不改变 F-J 输入 |

筛查差异时按信息流定位，不通过改色阶使图看起来接近：

| 首个不一致的位置 | 先查什么 |
| --- | --- |
| 输入或 EDWav | 读入维序、500 道共模孔径、是否重复预处理、小窗个数与秒数混淆、实际使用 `result(1)` |
| 原生 CCF / 计数 | 道对顺序与索引起点、共轭方向、有效阵列 PSD 分母、拒绝道段和每对有效窗数 |
| 原生 CCF 一致而最终 CCF 不同 | 分箱 / 速度滤波、原生 IFFT 缩放、端点网格、正负支对应平均、最终裁窗 |
| CCF 相似而谱幅值 / ridge 不同 | 是否将显示 RMS 归一化送入计算、完整半支到频谱的交接、H2 的 Hilbert 轴、`r dr` 权重、No-window、展示量与 findpeaks 趋势选择 |

保留正负支的原生复数 cache 才能检查方向不对称；最终镜像 CCF 通过对称性检查，
只能说明镜像输出符合接口，不能单独证明原始两支正确或折叠步骤正确。
