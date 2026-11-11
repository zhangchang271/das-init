#!/usr/bin/env python3
"""Prepare 600-s SJ-DAS waveforms with DASQt before the NyHt mCCFJ run.

The purpose of this program is intentionally narrow: it performs only the
time-domain DASQt preprocessing and materialises the requested local aperture
as one MAT file per 600-s record.  EDWav, PSD-normalised mCCFJ correlation,
GW mute and F-J are subsequently done by
``run_workflow.m``.

The complete 500-channel record is always processed *before* the target
aperture is selected.  In particular, DASQt common-mode removal therefore has
the full fibre segment as its reference, instead of the 50-channel local
window.  RMA/phase-only whitening is deliberately absent: the NyHt workflow
uses ``NF='PSD'`` in ``mCCFJ.correlate`` and must remain the sole spectral
normalisation.

The current DASQt checkout exposes the processing backend but imports some
optional file-format readers at module import time.  This job reads the local
HDF5 files with h5py, so lightweight stubs are installed only for those unused
optional readers when their packages are unavailable.  No DASQt processing
function is replaced.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import types
from dataclasses import asdict, dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import h5py
import numpy as np
from scipy.io import savemat


RAW_DATASET = "Acquisition/Raw[0]/RawData"
FILE_PATTERN = re.compile(
    r"^BlossomHill_(\d{8})_(\d{2})-\d{8}_(\d{2})_ch(\d+)-(\d+)\.h5$"
)
DEFAULT_DASQT_SOURCE = Path(__file__).resolve().parents[1] / "vendor" / "dasqt"


@dataclass(frozen=True)
class Segment:
    ordinal: int
    source_file: str
    source_file_index: int
    segment_index_in_file: int
    start_sample0: int
    start_time: str


@dataclass(frozen=True)
class Config:
    fs_hz: float
    channel_spacing_m: float
    gauge_length_m: float
    segment_seconds: int
    full_channel_first0: int
    full_channel_count: int
    target_channel_first0: int
    target_channel_count: int
    band_hz: tuple[float, float]
    butter_order: int
    tukey_alpha: float
    common_mode_removal: bool
    dasqt_source: str
    max_segments: int


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", type=Path, default=Path.cwd())
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--channel-first", type=int, default=0,
                        help="Zero-based target raw channel; default is physical channel 16700.")
    parser.add_argument("--channel-count", type=int, default=500)
    parser.add_argument("--full-channel-first", type=int, default=0)
    parser.add_argument("--full-channel-count", type=int, default=0,
                        help="0 means every channel in the HDF5 record (the default: all 500).")
    parser.add_argument("--fs-hz", type=float, default=200.0)
    parser.add_argument("--channel-spacing-m", type=float, default=1.0)
    parser.add_argument("--gauge-length-m", type=float, default=10.0)
    parser.add_argument("--segment-seconds", type=int, default=600)
    parser.add_argument("--max-segments", type=int, default=144,
                        help="144 is the complete first 24 h; 0 means all complete segments.")
    parser.add_argument("--band", type=float, nargs=2, default=(3.0, 30.0))
    parser.add_argument("--butter-order", type=int, default=4)
    parser.add_argument("--tukey-alpha", type=float, default=0.05)
    parser.add_argument("--no-common-mode-removal", action="store_true")
    parser.add_argument("--dasqt-source", type=Path, default=DEFAULT_DASQT_SOURCE)
    parser.add_argument("--overwrite", action="store_true")
    return parser.parse_args()


def parse_file_start(path: Path) -> datetime:
    match = FILE_PATTERN.match(path.name)
    if match is None:
        raise ValueError(f"Unexpected HDF5 filename: {path.name}")
    return datetime.strptime(match.group(1) + match.group(2), "%Y%m%d%H")


def discover_files(data_dir: Path) -> list[Path]:
    paths = sorted(data_dir.glob("BlossomHill_*.h5"), key=parse_file_start)
    if not paths:
        raise FileNotFoundError(f"No BlossomHill HDF5 files under {data_dir}")
    return paths


def build_inventory(files: list[Path], cfg: Config) -> tuple[list[Segment], list[dict[str, Any]], int]:
    """Validate input metadata and construct complete 600-s segment records."""
    samples_per_segment = int(round(cfg.segment_seconds * cfg.fs_hz))
    segments: list[Segment] = []
    inventory: list[dict[str, Any]] = []
    previous_end: datetime | None = None
    n_raw_channel: int | None = None

    for file_index, path in enumerate(files):
        with h5py.File(path, "r") as handle:
            dataset = handle[RAW_DATASET]
            n_sample, n_channel = (int(v) for v in dataset.shape)
            fs_hz = float(handle.attrs["sampling_rate_Hz"])
            start_text = str(handle.attrs["start_time"])
            end_text = str(handle.attrs["end_time"])
            channel_start = int(handle.attrs["channel_start"])
            channel_end = int(handle.attrs["channel_end"])
        if not np.isclose(fs_hz, cfg.fs_hz):
            raise ValueError(f"{path.name}: Fs={fs_hz:g}, expected {cfg.fs_hz:g}")
        if n_raw_channel is None:
            n_raw_channel = n_channel
        elif n_channel != n_raw_channel:
            raise ValueError(f"{path.name}: channel count {n_channel} differs from earlier files")

        full_count = cfg.full_channel_count or n_channel
        if cfg.full_channel_first0 < 0 or cfg.full_channel_first0 + full_count > n_channel:
            raise ValueError(f"{path.name}: full DASQt aperture is outside raw channels")
        if cfg.target_channel_first0 < cfg.full_channel_first0 or (
            cfg.target_channel_first0 + cfg.target_channel_count
            > cfg.full_channel_first0 + full_count
        ):
            raise ValueError(
                "The target aperture must lie inside the full DASQt preprocessing aperture"
            )

        start = datetime.strptime(start_text, "%Y-%m-%d %H:%M:%S")
        end = datetime.strptime(end_text, "%Y-%m-%d %H:%M:%S")
        gap = None if previous_end is None else (start - previous_end).total_seconds()
        inventory.append(
            {
                "file": path.name,
                "start_time": start_text,
                "end_time": end_text,
                "samples": n_sample,
                "channels": n_channel,
                "raw_channel_range": [channel_start, channel_end],
                "gap_from_previous_seconds": gap,
            }
        )
        for segment_index in range(n_sample // samples_per_segment):
            segments.append(
                Segment(
                    ordinal=len(segments) + 1,
                    source_file=path.name,
                    source_file_index=file_index,
                    segment_index_in_file=segment_index,
                    start_sample0=segment_index * samples_per_segment,
                    start_time=(start + timedelta(seconds=segment_index * cfg.segment_seconds)).strftime(
                        "%Y-%m-%d %H:%M:%S"
                    ),
                )
            )
        previous_end = end

    if cfg.max_segments > 0:
        segments = segments[: cfg.max_segments]
    if not segments:
        raise RuntimeError("No complete segments selected")
    assert n_raw_channel is not None
    return segments, inventory, n_raw_channel


def install_unused_io_dependency_stubs() -> None:
    """Let DASQt's processing backend import without optional SEG-Y/TDMS/SAC I/O.

    The DASQt checkout imports all format handlers at package import time even
    when callers directly provide a NumPy array.  The stubs fail on use; this
    program never calls those handlers because it reads BlossomHill HDF5 via
    h5py above.
    """
    try:
        import segyio  # noqa: F401
    except ModuleNotFoundError:
        sys.modules["segyio"] = types.ModuleType("segyio")

    try:
        import nptdms  # noqa: F401
    except ModuleNotFoundError:
        module = types.ModuleType("nptdms")
        module.TdmsFile = object
        module.TdmsWriter = object
        module.RootObject = object
        module.GroupObject = object
        module.ChannelObject = object
        sys.modules["nptdms"] = module

    try:
        import obspy  # noqa: F401
    except ModuleNotFoundError:
        module = types.ModuleType("obspy")
        module.Stream = object
        sys.modules["obspy"] = module


def load_dasqt_backend(source: Path):
    if not source.is_dir():
        raise FileNotFoundError(f"DASQt source was not found: {source}")
    source_text = str(source.resolve())
    if source_text not in sys.path:
        sys.path.insert(0, source_text)
    install_unused_io_dependency_stubs()
    from dasqt.features.signal_processing.backend.basic_tools.preprocessing import (
        cosine_taper,
        demeaning,
        detrending,
    )
    from dasqt.features.signal_processing.backend.basic_tools.filter import bandpass
    from dasqt.features.signal_processing.backend.advanced_tools.denoising import (
        common_mode_noise_removal,
    )
    return demeaning, detrending, cosine_taper, bandpass, common_mode_noise_removal


def dasqt_preprocess_full(
    raw_time_channel: np.ndarray,
    cfg: Config,
    backend: tuple[Any, Any, Any, Any, Any],
) -> np.ndarray:
    """Run the selected DASQt backend operations with its channel x time convention."""
    demeaning, detrending, cosine_taper, bandpass, common_mode_noise_removal = backend
    # DASQt backend functions operate channel x time.  The raw HDF5 layout is
    # time x channel, therefore the transpose is intentional and explicit.
    work = np.ascontiguousarray(np.asarray(raw_time_channel, dtype=np.float32).T)
    work[~np.isfinite(work)] = 0.0
    work = demeaning(work)
    work = detrending(work)
    work = cosine_taper(work, p=(0.0, cfg.tukey_alpha))
    work = bandpass(
        work,
        cfg.fs_hz,
        cfg.band_hz[0],
        cfg.band_hz[1],
        corners=cfg.butter_order,
        zerophase=True,
        detrend=False,
        taper=False,
    )
    if cfg.common_mode_removal:
        # The function projects each channel away from the full-fibre median
        # common mode.  Skip only the mathematically degenerate all-zero case.
        common = np.median(work, axis=0)
        if np.sum(common * common) > np.finfo(float).eps:
            work = common_mode_noise_removal(work)
    return np.ascontiguousarray(work.T, dtype=np.float32)


def target_validity(raw_target: np.ndarray) -> np.ndarray:
    finite = np.all(np.isfinite(raw_target), axis=0)
    dynamic = np.percentile(np.abs(np.nan_to_num(raw_target, copy=True)), 95, axis=0) > 0
    return np.asarray(finite & dynamic, dtype=np.uint8)


def segment_cache_path(output: Path, segment: Segment) -> Path:
    timestamp = segment.start_time.replace("-", "").replace(" ", "_").replace(":", "")
    return output / "segments" / f"segment_{segment.ordinal:03d}_{timestamp}.mat"


def write_segment(path: Path, wave: np.ndarray, valid: np.ndarray, segment: Segment, cfg: Config) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".mat.part")
    savemat(
        temporary,
        {
            "wave": wave,
            "raw_valid": valid.reshape(1, -1),
            "source_file": segment.source_file,
            "source_file_index": np.int32(segment.source_file_index + 1),
            "segment_index_in_file": np.int32(segment.segment_index_in_file + 1),
            "start_sample1": np.int64(segment.start_sample0 + 1),
            "start_time": segment.start_time,
            "fs_hz": np.float64(cfg.fs_hz),
            "channel_spacing_m": np.float64(cfg.channel_spacing_m),
            "gauge_length_m": np.float64(cfg.gauge_length_m),
            "raw_channel_first0": np.int32(cfg.target_channel_first0),
            "raw_channel_count": np.int32(cfg.target_channel_count),
            "dasqt_full_channel_first0": np.int32(cfg.full_channel_first0),
            "dasqt_full_channel_count": np.int32(cfg.full_channel_count),
            "preprocess_note": (
                "DASQt backend: per-channel demean, linear detrend, "
                f"Tukey(alpha={cfg.tukey_alpha:g}), zero-phase Butterworth "
                f"{cfg.band_hz[0]:g}-{cfg.band_hz[1]:g} Hz (order {cfg.butter_order}), "
                + ("full-array common-mode removal; " if cfg.common_mode_removal else "no common-mode removal; ")
                + "no DASQt frequency/time whitening; NyHt mCCFJ PSD is applied later."
            ),
        },
        do_compression=True,
        appendmat=False,
    )
    os.replace(temporary, path)


def segment_cache_key(source: Path, segment: Segment, cfg: Config) -> str:
    """Identify data, parameters and backend source before reusing a segment."""
    stat = source.stat()
    settings = asdict(cfg)
    settings.pop("max_segments")  # Extending a run does not change old segments.
    backend_root = Path(cfg.dasqt_source) / "dasqt/features/signal_processing/backend"
    backend_hashes = {}
    for name in ("basic_tools/preprocessing.py", "basic_tools/filter.py",
                 "advanced_tools/denoising.py", "advanced_tools/fdct.py"):
        backend_hashes[name] = hashlib.sha256((backend_root / name).read_bytes()).hexdigest()
    signature = {
        "config": settings,
        "segment": asdict(segment),
        "source_path": str(source.resolve()),
        "source_size": stat.st_size,
        "source_mtime_ns": stat.st_mtime_ns,
        "backend_hashes": backend_hashes,
        "preprocessor_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    }
    payload = json.dumps(signature, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode()).hexdigest()


def can_reuse_segment(path: Path, key: str) -> bool:
    try:
        sidecar = json.loads(path.with_suffix(".cache.json").read_text())
        stat = path.stat()
        return (sidecar["cache_key"] == key and sidecar["bytes"] == stat.st_size
                and sidecar["mtime_ns"] == stat.st_mtime_ns)
    except (OSError, ValueError, KeyError, TypeError):
        return False


def write_cache_sidecar(path: Path, key: str) -> None:
    stat = path.stat()
    metadata = {"cache_key": key, "bytes": stat.st_size, "mtime_ns": stat.st_mtime_ns}
    target = path.with_suffix(".cache.json")
    temporary = target.with_suffix(".json.part")
    temporary.write_text(json.dumps(metadata, sort_keys=True) + "\n")
    os.replace(temporary, target)


def main() -> None:
    args = parse_args()
    cfg = Config(
        fs_hz=float(args.fs_hz),
        channel_spacing_m=float(args.channel_spacing_m),
        gauge_length_m=float(args.gauge_length_m),
        segment_seconds=int(args.segment_seconds),
        full_channel_first0=int(args.full_channel_first),
        full_channel_count=int(args.full_channel_count),
        target_channel_first0=int(args.channel_first),
        target_channel_count=int(args.channel_count),
        band_hz=(float(args.band[0]), float(args.band[1])),
        butter_order=int(args.butter_order),
        tukey_alpha=float(args.tukey_alpha),
        common_mode_removal=not bool(args.no_common_mode_removal),
        dasqt_source=str(args.dasqt_source.resolve()),
        max_segments=int(args.max_segments),
    )
    if cfg.segment_seconds != 600:
        raise ValueError("The NyHt EDWav workflow uses fixed 600-s segments")
    if cfg.channel_spacing_m <= 0 or cfg.gauge_length_m <= 0:
        raise ValueError("Channel spacing and gauge length must be positive")
    if cfg.target_channel_count < 2:
        raise ValueError("At least two target channels are required")
    if not (0 < cfg.band_hz[0] < cfg.band_hz[1] < cfg.fs_hz / 2):
        raise ValueError(f"Invalid DASQt preprocessing band: {cfg.band_hz}")
    if not 0 <= cfg.tukey_alpha <= 1:
        raise ValueError("Tukey alpha must lie in [0, 1]")

    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    files = discover_files(args.data_dir.resolve())
    segments, inventory, n_raw_channel = build_inventory(files, cfg)
    full_count = cfg.full_channel_count or n_raw_channel
    cfg = Config(**(asdict(cfg) | {"full_channel_count": full_count}))
    backend = load_dasqt_backend(Path(cfg.dasqt_source))
    sample_count = int(round(cfg.segment_seconds * cfg.fs_hz))
    target_rel0 = cfg.target_channel_first0 - cfg.full_channel_first0
    records: list[dict[str, Any]] = []

    print(
        "DASQt preprocessing: "
        f"{len(segments)} x {cfg.segment_seconds}s; full channels "
        f"{cfg.full_channel_first0}--{cfg.full_channel_first0 + cfg.full_channel_count - 1}; "
        f"target {cfg.target_channel_first0}--{cfg.target_channel_first0 + cfg.target_channel_count - 1}",
        flush=True,
    )
    for number, segment in enumerate(segments, start=1):
        cache_path = segment_cache_path(output, segment)
        source = files[segment.source_file_index]
        key = segment_cache_key(source, segment, cfg)
        if not args.overwrite and can_reuse_segment(cache_path, key):
            records.append(asdict(segment) | {"cache_file": str(cache_path.name), "cache_key": key, "status": "reused"})
            print(f"DASQt {number:03d}/{len(segments):03d}: reused {segment.start_time}", flush=True)
            continue

        with h5py.File(source, "r") as handle:
            raw_full = np.asarray(
                handle[RAW_DATASET][
                    segment.start_sample0: segment.start_sample0 + sample_count,
                    cfg.full_channel_first0: cfg.full_channel_first0 + cfg.full_channel_count,
                ]
            )
        if raw_full.shape != (sample_count, cfg.full_channel_count):
            raise RuntimeError(f"{source.name}: incomplete source read for {segment.start_time}")
        valid = target_validity(raw_full[:, target_rel0:target_rel0 + cfg.target_channel_count])
        processed = dasqt_preprocess_full(raw_full, cfg, backend)
        wave = processed[:, target_rel0:target_rel0 + cfg.target_channel_count]
        write_segment(cache_path, wave, valid, segment, cfg)
        write_cache_sidecar(cache_path, key)
        records.append(asdict(segment) | {"cache_file": str(cache_path.name), "cache_key": key, "status": "written"})
        print(
            f"DASQt {number:03d}/{len(segments):03d}: {segment.start_time}; "
            f"valid target channels={int(valid.sum())}/{cfg.target_channel_count}",
            flush=True,
        )

    manifest = {
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "workflow": "DASQt full-record preprocessing cache for NyHt PSD-mCCFJ",
        "config": asdict(cfg),
        "input_inventory": inventory,
        "segments": records,
        "normalization_note": "DASQt RMA/time whitening is disabled. The downstream NyHt call uses NF='PSD'.",
    }
    with (output / "dasqt_preprocess_manifest.json").open("w", encoding="utf-8") as stream:
        json.dump(manifest, stream, indent=2, ensure_ascii=False)
        stream.write("\n")
    print(f"Completed DASQt cache: {output}", flush=True)


if __name__ == "__main__":
    main()
