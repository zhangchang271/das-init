#!/usr/bin/env python3
"""Verify the frozen algorithm sources and the minimal headless Python stack."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import sys
from importlib.metadata import version
from pathlib import Path


def verify_vendor(root: Path) -> int:
    manifest = json.loads((root / "vendor/manifest.json").read_text())
    for entry in manifest["files"]:
        path = root / entry["path"]
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest != entry["sha256"]:
            raise RuntimeError(f"Frozen source differs from the manifest: {entry['path']}")
    return len(manifest["files"])


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    count = verify_vendor(root)
    if sys.version_info[:2] != (3, 12):
        raise RuntimeError("Use Python 3.12 to reproduce the recorded environment")
    import h5py  # noqa: F401
    import numpy as np
    import scipy  # noqa: F401

    spec = importlib.util.spec_from_file_location("prepare_dasqt_check", root / "python/prepare_dasqt.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    backend = module.load_dasqt_backend(root / "vendor/dasqt")
    if len(backend) != 5:
        raise RuntimeError("The DASQt backend did not load all five processing operations")
    for package in ("numpy", "scipy", "h5py"):
        print(f"{package}={version(package)}")
    print(f"Python {sys.version.split()[0]}; {count} frozen sources verified; headless DASQt imports OK")


if __name__ == "__main__":
    main()
