#!/usr/bin/env python3
"""Create a small deterministic BlossomHill HDF5 record for deployment tests."""

from __future__ import annotations

import argparse
from datetime import datetime, timedelta
from pathlib import Path

import h5py
import numpy as np


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=Path("demo_data"))
    parser.add_argument("--channels", type=int, default=8)
    parser.add_argument("--duration-seconds", type=int, default=600)
    parser.add_argument("--fs-hz", type=float, default=200.0)
    parser.add_argument("--channel-spacing-m", type=float, default=10.0)
    parser.add_argument("--seed", type=int, default=20261111)
    parser.add_argument("--overwrite", action="store_true")
    return parser.parse_args()


def make_record(
    channels: int, duration_seconds: int, fs_hz: float,
    channel_spacing_m: float, seed: int,
) -> np.ndarray:
    samples = int(round(duration_seconds * fs_hz))
    time = np.arange(samples, dtype=np.float64) / fs_hz
    position = np.arange(channels, dtype=np.float64) * channel_spacing_m
    wave = np.zeros((samples, channels), dtype=np.float64)

    for frequency, amplitude, velocity, phase in (
        (6.0, 1.0, 260.0, 0.0),
        (9.0, 0.7, 220.0, 0.4),
        (13.0, 0.45, 180.0, -0.7),
    ):
        delay = position / velocity
        wave += amplitude * np.sin(
            2.0 * np.pi * frequency * (time[:, None] - delay[None, :]) + phase
        )

    rng = np.random.default_rng(seed)
    channel_gain = 0.9 + 0.2 * rng.random(channels)
    wave *= channel_gain[None, :]
    wave += 0.12 * rng.standard_normal((samples, channels))
    return np.asarray(wave, dtype=np.float32)


def main() -> None:
    args = parse_args()
    if args.channels < 2:
        raise ValueError("--channels must be at least 2")
    if args.fs_hz <= 0:
        raise ValueError("--fs-hz must be positive")
    if args.channel_spacing_m <= 0:
        raise ValueError("--channel-spacing-m must be positive")
    if args.duration_seconds < 600 or args.duration_seconds % 600:
        raise ValueError("--duration-seconds must be a positive multiple of 600")

    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    end = datetime(2023, 9, 20) + timedelta(seconds=args.duration_seconds)
    filename = (
        f"BlossomHill_20230920_00-"
        f"{end:%Y%m%d}_{end:%H}_ch00000-{args.channels - 1:05d}.h5"
    )
    path = output_dir / filename
    if path.exists() and not args.overwrite:
        raise FileExistsError(f"Demo file already exists: {path}; use --overwrite")

    wave = make_record(
        args.channels, args.duration_seconds, args.fs_hz,
        args.channel_spacing_m, args.seed,
    )
    with h5py.File(path, "w") as handle:
        handle.create_dataset(
            "Acquisition/Raw[0]/RawData",
            data=wave,
            chunks=(min(wave.shape[0], 8192), wave.shape[1]),
            compression="gzip",
            compression_opts=1,
        )
        handle.attrs["sampling_rate_Hz"] = float(args.fs_hz)
        handle.attrs["start_time"] = "2023-09-20 00:00:00"
        handle.attrs["end_time"] = end.strftime("%Y-%m-%d %H:%M:%S")
        handle.attrs["channel_start"] = 0
        handle.attrs["channel_end"] = args.channels - 1

    print(f"Created {path} ({wave.shape[0]} samples x {wave.shape[1]} channels)")


if __name__ == "__main__":
    main()
