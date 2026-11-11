#!/usr/bin/env python3
"""Extract one real 600-second BlossomHill DAS segment for a small preview run."""

from __future__ import annotations

import argparse
from datetime import datetime, timedelta
from pathlib import Path

import h5py


DATASET = "Acquisition/Raw[0]/RawData"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input_file", type=Path)
    parser.add_argument("--output-dir", type=Path, default=Path("demo_data"))
    parser.add_argument("--segment-index", type=int, default=0,
                        help="Zero-based 600-second segment within the input file.")
    parser.add_argument("--overwrite", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.segment_index < 0:
        raise ValueError("--segment-index must be nonnegative")

    input_file = args.input_file.resolve()
    output_dir = args.output_dir.resolve()
    samples_per_segment = 600 * 200
    output_dir.mkdir(parents=True, exist_ok=True)

    with h5py.File(input_file, "r") as source:
        raw = source[DATASET]
        if raw.ndim != 2 or raw.shape[1] != 500:
            raise ValueError(f"Expected a time x 500-channel BlossomHill array, got {raw.shape}")
        if float(source.attrs["sampling_rate_Hz"]) != 200:
            raise ValueError("This demo extractor expects a 200 Hz source")
        start = datetime.strptime(str(source.attrs["start_time"]), "%Y-%m-%d %H:%M:%S")
        first = args.segment_index * samples_per_segment
        last = first + samples_per_segment
        if last > raw.shape[0]:
            raise ValueError("Selected 600-second segment extends past the input file")
        segment_start = start + timedelta(seconds=args.segment_index * 600)
        segment_end = segment_start + timedelta(seconds=600)
        channel_start = int(source.attrs["channel_start"])
        channel_end = int(source.attrs["channel_end"])
        filename = (
            f"BlossomHill_{segment_start:%Y%m%d}_{segment_start:%H}-"
            f"{segment_end:%Y%m%d}_{segment_end:%H}_"
            f"ch{channel_start:05d}-{channel_end:05d}.h5"
        )
        output_file = output_dir / filename
        if output_file.exists() and not args.overwrite:
            raise FileExistsError(f"Demo file exists: {output_file}; use --overwrite")

        segment = raw[first:last, :]
        with h5py.File(output_file, "w") as target:
            target.create_dataset(
                DATASET,
                data=segment,
                chunks=(min(samples_per_segment, 12000), min(raw.shape[1], 83)),
                compression="gzip",
                compression_opts=1,
                shuffle=True,
            )
            for name, value in source.attrs.items():
                target.attrs[name] = value
            target.attrs["start_time"] = segment_start.strftime("%Y-%m-%d %H:%M:%S")
            target.attrs["end_time"] = segment_end.strftime("%Y-%m-%d %H:%M:%S")

    print(
        f"Extracted {output_file}: {segment.shape[0]} samples x {segment.shape[1]} channels, "
        f"{segment_start} to {segment_end}"
    )


if __name__ == "__main__":
    main()
