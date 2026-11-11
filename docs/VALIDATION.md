# 验证记录

部署测试使用小型合成数据；另用原始 San Jose 2023-09-20 全天数据完成了 500 道流程和 QC 频散谱复现。

| 检查 | 结果 |
| --- | --- |
| 原始入口保护 | 两份原 SJDAS 入口的 SHA-256 与整理前一致 |
| 算法源码保护 | 8 份第三方源码与原文件逐字节一致；Git 保留其原始行尾 |
| Python 独立加载 | Python 3.12.4，NumPy 1.26.4，SciPy 1.13.1，h5py 3.12.1；只加载仓库内 DASQt 后端 |
| 隔离部署 | 从 Git 压缩包解压到临时目录，新建 venv，仅安装 requirements.txt；环境检查和全部 Python 测试通过 |
| Python 部署测试 | 3 项通过；120000×4 的 600 s 合成 HDF5 能生成 float32 MAT |
| 预处理范围 | 截取 2 道的结果与先处理全部 4 道后截取逐点一致 |
| 缓存 | 同配置复用；改变带通或修改原文件后重建 |
| 启动路径 | 含空格、单引号的配置和数据路径可传递；配置中的 stage 能保留 |
| MATLAB 静态语法 | MISS_HIT 对入口、主控、配置、环境检查、路径引用和测试共 6 个文件检查通过 |
| MATLAB 小型测试 | R2021a Update 8 的 3 项测试均报告 Passed=true、Failed=false、Incomplete=false |
| San Jose 全量计算 | MATLAB R2021a Update 8；144 个 600 s 片段、500 道，生成 EDWav 筛选、30 Hz CCF 和默认 1–14.9 Hz 综合 F-J |
| CCF 缓存对比 | 与原项目缓存频率轴、500 个偏移和 `count_sum` 完全一致；计数范围均为 106–124，CCF 相对 Frobenius 差为 `5.82e-6` |
| 默认 preview | 主入口生成参考图样式三联图：无 mute、0–3 s CCF、1–14.9 Hz H2 F-J；配置范围为 1–15 Hz，ridge 保留主流程的 findpeaks 趋势追踪 |
| 频散谱复现 | 新旧 F-J 网格相同（1.0–14.9 Hz、100–800 m/s），谱相对 Frobenius 差为 `1.16e-5` |

MATLAB 测试直接对比有效道平均功率谱的 PSD 公式，并检查被拒绝道对的计数为零、
整体幅度缩放不改变 PSD CCF；另检查 JSON 配置和 shell 参数传递。
小型 MATLAB 测试进程在成功断言及完成标记之后仍返回退出码 129；San Jose 全量计算和默认 preview
则在 MATLAB R2021a Update 8 下成功完成。mCCFJ 建议 R2023a 或更新版本，环境检查会提示较旧版本，
但不再把推荐版本当作硬性限制。

本次没有验证目标机器的 MATLAB/工具箱许可、跨机一致性、交互 polygon 或最终衰减。QC 结果中
1–3 Hz 低于 DASQt 预处理带通下限；建议将 3–12 Hz 作为主要检查范围。
参考图的预览 ridge 使用相邻频率 ±40 个速度采样点内取最大值；默认主流程图继续使用
`findpeaks` 加趋势追踪的 ridge，因此黑线不要求与参考预览线逐点相同。
