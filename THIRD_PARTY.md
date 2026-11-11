# 第三方来源与授权状态

本项目暂未指定统一开源许可证，不能把本目录中的全部文件视为可按同一许可证再分发。

| 文件 | 来源 | 原文件中的声明 |
| --- | --- | --- |
| `vendor/matlab/mCCFJ.m` | NyHtQInv / 2026地震算法研讨会材料-杨博 | Copyright © 2026 Bo Yang，All rights reserved；Timestamp 2026-07-15 |
| `vendor/matlab/EDWav.m` | 同上 | Copyright (C) 2024 Bo Yang；未发现随附的明确再分发许可证 |
| `vendor/matlab/GW_mute.m`、`GW_mute1.m` | NyHtQInv / core | 原文件没有许可证头；未另行指定 |
| DASQt 四个后端模块 | DASQt `features/signal_processing/backend` | 来源项目 `pyproject.toml` 声明 MIT；保留原模块作者注释 |

最小 DASQt 快照包括 `preprocessing.py`、`filter.py`、`denoising.py`、`fdct.py`。
没有打包 DASQt GUI、其他功能插件或 MATLAB 安装文件。
每个原样保存文件的 SHA-256 及相对来源见 `vendor/manifest.json`。

包含上述杨博和 NyHt 文件的版本先用于私有研究仓库。公开发布前需取得或确认对应再分发授权，
并补齐正式许可证文本；本说明本身不授予第三方代码的使用或再分发许可。

使用 mCCFJ 的研究应按源码要求引用：Yang, B., Meng, H., Yuan, S., & Chen, X. (2025).
Reliable Multimodal Attenuation Estimation of Surface Waves Using Diffuse Ambient Noise: Theory and Applications.
Journal of Geophysical Research: Solid Earth, 130, e2025JB031418.
https://doi.org/10.1029/2025JB031418
