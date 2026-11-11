"""Small synthetic tests; no original DAS files or MATLAB licence required."""
from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import h5py
import numpy as np
from scipy.io import loadmat

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from check_python import verify_vendor


class DeploymentTests(unittest.TestCase):
    def test_small_demo_generator_writes_blossomhill_record(self):
        with tempfile.TemporaryDirectory(prefix="das-demo-") as directory:
            output = Path(directory) / "demo"
            subprocess.run(
                [sys.executable, str(ROOT / "scripts/make_demo_data.py"),
                 "--output-dir", str(output), "--channels", "4",
                 "--duration-seconds", "600"],
                check=True,
                text=True,
                capture_output=True,
            )
            files = list(output.glob("BlossomHill_*.h5"))
            self.assertEqual(len(files), 1)
            with h5py.File(files[0], "r") as handle:
                data = handle["Acquisition/Raw[0]/RawData"]
                self.assertEqual(data.shape, (120000, 4))
                self.assertEqual(data.dtype, np.dtype("float32"))
                self.assertEqual(float(handle.attrs["sampling_rate_Hz"]), 200.0)
                self.assertEqual(int(handle.attrs["channel_end"]), 3)

    def test_frozen_sources_are_complete_and_unchanged(self):
        self.assertEqual(verify_vendor(ROOT), 8)

    def run_preprocessing(self, data: Path, output: Path, *extra: str):
        command = [sys.executable, str(ROOT / "python/prepare_dasqt.py"),
                   "--data-dir", str(data), "--output-dir", str(output),
                   "--channel-first", "0", "--channel-count", "4",
                   "--max-segments", "1", *extra]
        return subprocess.run(command, text=True, capture_output=True, check=True)

    def test_cache_resume_parameter_change_and_full_array_common_mode(self):
        with tempfile.TemporaryDirectory(prefix="das-workflow-") as directory:
            base = Path(directory)
            data = base / "data with spaces and 'quote'"
            data.mkdir()
            path = data / "BlossomHill_20230920_00-20230920_01_ch16700-16703.h5"
            rng = np.random.default_rng(731)
            time = np.arange(120000, dtype=np.float64) / 200
            shared = np.sin(2 * np.pi * 8 * time)
            raw = np.column_stack([
                (1 + index / 3) * shared + np.sin(2 * np.pi * (12 + index) * time)
                + 0.1 * rng.standard_normal(time.size) for index in range(4)
            ]).astype(np.float32)
            with h5py.File(path, "w") as handle:
                handle.create_dataset("Acquisition/Raw[0]/RawData", data=raw)
                handle.attrs["sampling_rate_Hz"] = 200
                handle.attrs["start_time"] = "2023-09-20 00:00:00"
                handle.attrs["end_time"] = "2023-09-20 00:10:00"
                handle.attrs["channel_start"] = 16700
                handle.attrs["channel_end"] = 16703

            full = base / "full output"
            first = self.run_preprocessing(data, full)
            self.assertIn("valid target channels=4/4", first.stdout)
            segment = next((full / "segments").glob("*.mat"))
            fields = loadmat(segment)
            self.assertEqual(fields["wave"].shape, (120000, 4))
            self.assertEqual(fields["wave"].dtype, np.float32)
            self.assertTrue(np.all(fields["raw_valid"] == 1))
            self.assertTrue(np.isfinite(fields["wave"]).all())
            old_stat = segment.stat().st_mtime_ns

            resumed = self.run_preprocessing(data, full)
            self.assertIn("reused", resumed.stdout)
            self.assertEqual(segment.stat().st_mtime_ns, old_stat)

            # Selecting two channels must keep the common-mode reference
            # computed from all four, rather than changing the aperture.
            subset = base / "subset"
            self.run_preprocessing(data, subset, "--channel-count", "2")
            subset_wave = loadmat(next((subset / "segments").glob("*.mat")))["wave"]
            np.testing.assert_array_equal(subset_wave, fields["wave"][:, :2])

            changed = self.run_preprocessing(data, full, "--band", "4", "25")
            self.assertNotIn(": reused", changed.stdout)
            self.assertFalse(np.array_equal(loadmat(segment)["wave"], fields["wave"]))
            manifest = json.loads((full / "dasqt_preprocess_manifest.json").read_text())
            self.assertEqual(manifest["config"]["band_hz"], [4, 25])

            # Editing the source must invalidate a segment even when its name
            # and processing options stay the same.
            with h5py.File(path, "r+") as handle:
                handle["Acquisition/Raw[0]/RawData"][0, 0] += 2
            modified = self.run_preprocessing(data, full, "--band", "4", "25")
            self.assertNotIn(": reused", modified.stdout)

    def test_batch_launcher_passes_literal_paths_and_inherits_config_stage(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            config = base / "path with 'quote'.json"
            config.write_text('{"stage":"ccf"}')
            fake = base / "matlab"
            capture = base / "arguments.json"
            fake.write_text("#!" + sys.executable + "\n"
                            "import json,os,sys\n"
                            "from pathlib import Path\n"
                            "Path(os.environ['CAPTURE']).write_text(json.dumps({"
                            "'argv':sys.argv[1:],'config':os.environ['DAS_WORKFLOW_CONFIG'],"
                            "'stage':os.environ['DAS_WORKFLOW_STAGE']}))\n")
            fake.chmod(0o755)
            import os
            env = os.environ | {"MATLAB_BIN": str(fake), "CAPTURE": str(capture)}
            subprocess.run(["bash", str(ROOT / "scripts/run.sh"), str(config)], env=env, check=True)
            result = json.loads(capture.read_text())
            self.assertEqual(result["config"], str(config.resolve()))
            self.assertEqual(result["stage"], "")
            self.assertEqual(result["argv"][0], "-batch")
            self.assertNotIn(str(config), result["argv"][1])
            denied = subprocess.run(["bash", str(ROOT / "scripts/run.sh"), str(config), "pick"],
                                    env=env, capture_output=True)
            self.assertEqual(denied.returncode, 2)


if __name__ == "__main__":
    unittest.main()
