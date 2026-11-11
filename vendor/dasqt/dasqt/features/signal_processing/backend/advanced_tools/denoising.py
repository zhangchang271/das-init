# Purpose: Remove noise from data
# Author: Minzhe Hu, Zefeng Li
# Date: 2024.5.13
# Email: hmz2018@mail.ustc.edu.cn
import numpy as np
from copy import deepcopy
from scipy.ndimage import median_filter
from scipy.interpolate import interp1d
from ..basic_tools.preprocessing import padding
from .fdct import fdct_wrapping, ifdct_wrapping


def spike_removal(data, nch=50, nsp=5, thresh=10):
    """
    Use a median filter to remove high-strain spikes in the data. Modified from
    https://github.com/atterholt/curvelet-denoising/blob/main/MedianFilter.m

    :param data: numpy.ndarray. Data to remove spikes from.
    :param nch: int. Number of channels over which to compute the median.
    :param nsp: int. Number of sampling points over which to compute the median.
    :param thresh: Ratio threshold over the median over which a number is
        considered to be an outlier.
    :return: numpy.ndarray. Data with spikes removed.
    """
    absdata = np.abs(data)

    medians1 = median_filter(absdata, (nch, 1))
    medians = median_filter(medians1, (1, nsp))
    ratio = absdata / medians  # comparisons matrix
    
    print(medians.shape, absdata.shape, ratio.mean(),ratio.max(),ratio.min())

    # find the bad values and interpolate with their neighbors
    data_dn = data.copy()
    out_i, out_j = np.where(ratio > thresh)
    for j in set(out_j):
        bch = out_i[out_j == j]
        gch = list(set(range(len(data))) - set(bch))
        f = interp1d(gch, data[gch, j], bounds_error=False,
                     fill_value=(data[gch[0], j], data[gch[-1], j]))
        data_dn[bch, j] = f(bch)

    return data_dn


def common_mode_noise_removal(data, method='median'):
    """
    Remove common mode noise (sometimes called horizontal noise) from data.

    :param data: numpy.ndarray. Data to remove common mode noise.
    :param method:str. Method for extracting commmon mode noise. 'median' or
        'mean'
    :return: numpy.ndarray. Denoised data.
    """
    nch, nt = data.shape
    if method == 'median':
        common = np.median(data, 0)
    elif method == 'mean':
        common = np.mean(data, 0)

    xx = np.sum(common ** 2)
    data_dn = np.zeros((nch, nt))
    for i in range(nch):
        xc = np.sum(common * data[i])
        data_dn[i] = data[i] - xc / xx * common

    return data_dn


def _noise_level(data, finest=2, nbscales=None, nbangles=16, percentile=95):
    """
    Find threshold for curvelet denoising with noise record.

    :param data: numpy.ndarray. Noise data.
    :param nbscales: int. Number of scales including the coarsest wavelet level.
        Default set to ceil(log2(min(M,N)) - 3).
    :param nbangles: int. Number of angles at the 2nd coarsest level,
        minimum 8, must be a multiple of 4.
    :param percentile: number. The threshold is taken as this percentile of the
        curvelet coefficient of the noise record
    :return: 2-D list. Threshold for curvelet coefficients.
    """
    C = fdct_wrapping(data, is_real=True, finest=finest, nbscales=nbscales,
                      nbangles_coarse=nbangles)

    E_noise = []
    for s in range(len(C)):
        E_noise.append([])
        for w in range(len(C[s])):
            threshold = np.percentile(abs(C[s][w]), percentile)
            E_noise[s].append(threshold)

    return E_noise


def _knee_points(C, factor=0.2):
    """
    Find threshold for curvelet denoising without noise record.

    :param C: 2-D list of np.ndarray. Array of curvelet coefficients.
    :param factor: float. Multiplication factor from 0 to 1. Small factor
        corresponds to conservative strategy.
    :return: 2-D list. Threshold for curvelet coefficients.
    """
    E_knee = []
    for s in range(len(C)):
        E_knee.append([])
        for w in range(len(C[s])):
            F, x = np.histogram(abs(C[s][w]), density=True)
            x = (x[1:] + x[:-1]) / 2
            F = np.cumsum(F) / np.sum(F)
            slope = (x[-1] - x[0]) / (F[-1] - F[0])
            tiltedplot = x - (slope * F)
            idx = np.argmin(tiltedplot)
            E_knee[s].append(x[idx] * factor)

    return E_knee


def _velocity_bin(nbangles, fs, dx):
    v_bounds = np.zeros(nbangles // 4 + 1)
    half = nbangles // 8
    v_bounds[half] = fs * dx
    np.seterr(divide='ignore')
    for i in range(half):
        v_bounds[i] = i / half * fs * dx
        v_bounds[half + i + 1] = np.divide(fs * dx, 1 - (i + 1) / half)

    np.seterr(divide='warn')
    v_lows = list(range(half - 1, -1, -1)) + list(range(half * 2)) + \
        list(range(2 * half - 1, half - 1, -1))
    velocity = []
    for i in range(nbangles // 2):
        v_low = v_bounds[v_lows[i]]
        v_high = v_bounds[v_lows[i] + 1]
        velocity.append([v_low, v_high])
    velocity = np.array(velocity * 2)
    for i in range(half):
        velocity[i] = -1 * velocity[i][::-1]
        velocity[3 * half + i] = -1 * velocity[3 * half + i][::-1]
        velocity[4 * half + i] = -1 * velocity[4 * half + i][::-1]
        velocity[7 * half + i] = -1 * velocity[7 * half + i][::-1]
    return velocity


def _mask_factor(velocity, vmin, vmax, flag=0):
    if flag:
        if flag == -1:
            vmin = -vmax
            vmax = -vmin
    else:
        half = len(velocity) // 8
        for i in range(half):
            velocity[i] = -1 * velocity[i][::-1]
            velocity[3 * half + i] = -1 * velocity[3 * half + i][::-1]
            velocity[4 * half + i] = -1 * velocity[4 * half + i][::-1]
            velocity[7 * half + i] = -1 * velocity[7 * half + i][::-1]

    factors = np.zeros(len(velocity))
    for i, (v_low, v_high) in enumerate(velocity):
        v1 = max(v_low, vmin)
        v2 = min(v_high, vmax)
        if v1 < v2:
            if v_high == np.inf or v_low == -np.inf:
                factors[i] = 1
            else:
                factors[i] = np.divide(v2 - v1, v_high - v_low)

    return factors


def curvelet_denoising(data, choice=0, pad=0.3, noise=None, noise_perc=95,
                       knee_fac=0.2, soft_thresh=True, vmin=0, vmax=np.inf,
                       flag=0, dx=None, fs=None, mode='remove',
                       scale_begin=3, nbscales=None, nbangles=16, finest=2):
    """
    Use curevelet transform to filter stochastic or/and cooherent noise.
    Modified from
    https://github.com/atterholt/curvelet-denoising/blob/main/CurveletDenoising.m
    {Atterholt et al., 2022 , Geophys. J. Int.}

    :param data: numpy.ndarray. Data to denoise.
    :param choice: int. 0 for Gaussian denoising using soft thresholding, 1 for
        velocity filtering using the standard FK methodology and 2 for both.
    :param pad: float or sequence of floats. Each float means padding percentage
        before FFT for corresponding dimension. If set to 0.1 will pad 5% before
        the beginning and after the end.
    :param noise: numpy.ndarray or daspy.Section. Noise record as reference.
    :param noise_perc: number. The threshold is taken as this percentile of the
        curvelet coefficient of the noise record. (only used when noise is
        specified)
    :param knee_fac: float. Multiplication factor from 0 to 1. Small factor
        corresponds to conservative strategy. (only used when noise is not
        specified)
    :param soft_thresh: bool. True for soft thresholding and False for hard
        thresholding.
    :param vmin, vmax: float. Velocity range in m/s.
    :param flag: -1 choose only negative apparent velocities, 0 choose both
        postive and negative apparent velocities, 1 choose only positive
        apparent velocities.
    :param dx: Channel interval in m.
    :param fs: Sampling rate in Hz.
    :param mode: str. Only available when choice in (1,2). 'remove' for
        denoising, 'retain' for extraction, and 'decompose' for decomposition.
    :param scale_begin: int. The beginning scale to do coherent denoising.
    :param nbscales: int. Number of scales including the coarsest wavelet level.
        Default set to ceil(log2(min(M,N)) - 3).
    :param nbangles: int. Number of angles at the 2nd coarsest level,
        minimum 8, must be a multiple of 4.
    :param finest: int. Objects at the finest scale. 1 for curvelets, 2 for
        wavelets. Curvelets are more precise while wavelets are more efficient.
    :return: numpy.ndarray. Denoised data.

    :param data：numpy.ndarray。要去噪的数据。
    :param choice：int。0 表示使用软阈值的高斯去噪，1 表示使用标准 FK 方法的速度过滤，2 表示两者。
    :param pad：浮点数或浮点数序列。每个浮点数表示在相应维度的 FFT 之前填充的百分比。如果设置为 0.1，将在开始之前和结束之后填充 5%。
    :param noise：numpy.ndarray 或 daspy.Section。噪声记录作为参考。
    :param noise_perc：数字。阈值取为噪声记录的曲线波系数的百分位数。（仅在指定噪声时使用）
    :param knee_fac：浮点数。乘法因子从 0 到 1。小因子对应于保守策略。（仅在未指定噪声时使用）
    :param soft_thresh：布尔值。软阈值为 True，硬阈值为 False。
    :param vmin, vmax：浮点数。速度范围（单位：m/s）。
    :param flag：-1 仅选择负视速，0 选择正视速和负视速，1 仅选择正视速。
    :param dx：通道间隔（单位：m）。
    :param fs：采样率（单位：Hz）。
    :param mode：str。仅在选择 (1,2) 时可用。'remove' 用于去噪，'retain' 用于提取，'decompose' 用于分解。
    :param scale_begin：int。进行相干去噪的起始尺度。
    :param nbscales：int。包括最粗小波级的尺度数。默认设置为 ceil(log2(min(M,N)) - 3)。
    :param nbangles: int。第二粗略级别的角度数，最小为 8，必须是 4 的倍数。
    :param finest: int。最精细尺度的对象。1 表示曲线波，2 表示小波。曲线波更精确，而小波更高效。
    :return: numpy.ndarray。去噪数据。


    """
    if pad is None or pad is False:
        pad = 0
    dn = np.round(np.array(pad) * data.shape).astype(int)
    data_pd = padding(data, dn)

    C = fdct_wrapping(data_pd, is_real=True, finest=finest, nbscales=nbscales,
                      nbangles_coarse=nbangles)

    # apply Gaussian denoising
    if choice in (0, 2):
        # define threshold
        if noise is None:
            E = _knee_points(C, factor=knee_fac)
        else:
            if not isinstance(noise, np.ndarray):
                noise = noise.data
            noise_pd = padding(noise,
                               np.array(data_pd.shape) - np.array(noise.shape))
            E = _noise_level(noise_pd, finest=finest, nbscales=nbscales,
                             nbangles=nbangles, percentile=noise_perc)
        for s in range(1, len(C)):
            for w in range(len(C[s])):
                # first do a hard threshold
                C[s][w] = C[s][w] * (abs(C[s][w]) > abs(E[s][w]))
                if soft_thresh:
                    # soften the existing coefficients
                    C[s][w] = np.sign(C[s][w]) * (abs(C[s][w]) - abs(E[s][w]))

    # apply velocity filtering
    if choice in (1, 2):
        if dx is None or fs is None:
            raise ValueError('Please set both dx and fs.')

        if mode == 'decompose':
            lst = list(range(scale_begin - 1)) 
            if finest == 2:
                lst.append(len(C) - 1)
            for s in lst:
                for w in range(len(C[s])):
                    C[s][w] /= 2
            C_rt = deepcopy(C)

        for s in range(scale_begin - 1, len(C) - finest + 1):
            nbangles = len(C[s])
            velocity = _velocity_bin(nbangles, fs, dx)
            factors = _mask_factor(velocity, vmin, vmax, flag=flag)
            for w in range(nbangles):
                if mode == 'retain':
                    C[s][w] *= factors[w]
                elif mode == 'remove':
                    C[s][w] *= 1 - factors[w]
                elif mode == 'decompose':
                    C[s][w] *= factors[w]
                    C_rt[s][w] *= 1 - factors[w]

    # perform the inverse curvelet transform
    data_dn = padding(ifdct_wrapping(C, is_real=True, size=data_pd.shape), dn,
                      reverse=True)
    
    if mode == 'decompose':
        data_n = padding(ifdct_wrapping(C_rt, is_real=True, size=data_pd.shape),
                         dn, reverse=True)
        return data_dn, data_n
    else:
        return data_dn