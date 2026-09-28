#!/usr/bin/env python3
"""Regression checks for standard and composite factory discovery."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

BIN = Path(__file__).resolve().parent


class Profiles(unittest.TestCase):
    def test_registry_and_doctor_agree(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for profile in ("standard", "composite"):
                factory = root / f"{profile}-factory"
                factory.mkdir()
                (factory / "README.md").write_text("# Test\n")
                (factory / "R&D").mkdir()
                if profile == "standard":
                    for name in ("dashboards", "decisions", "logs", "experiments", "captures", "renders"):
                        (factory / "R&D" / name).mkdir()
                releases = factory / ("releases" if profile == "standard" else "archives")
                releases.mkdir()
                lanes = {}
                for name in ("dev", "next", "live"):
                    path = factory / name
                    path.mkdir()
                    subprocess.run(["git", "init", "-q", str(path)], check=True)
                    subprocess.run(["git", "-C", str(path), "-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-q", "--allow-empty", "-m", "init"], check=True)
                    lanes[name] = name
                cfg = {"project": profile, "obeya": {"stations": "echo '{}'"}}
                if profile == "standard":
                    cfg.update(lanes=lanes, commands={"test": "true"}, distribution={"format": "zip"})
                else:
                    cfg.update(profile="composite", framework=lanes, releases={"root": "archives"})
                (factory / "factory.json").write_text(json.dumps(cfg))
                result = subprocess.run(["bash", str(BIN / "factory-doctor.sh"), "--factory", str(factory)], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            out = root / "registry"
            subprocess.run(["bash", str(BIN / "factory-registry.sh"), "--root", str(root), "--out", str(out)], check=True, capture_output=True)
            rows = json.loads((out / "factories.json").read_text())["factories"]
            self.assertEqual([(r["profile"], r["status"], r["issues"]) for r in rows],
                             [("composite", "ok", []), ("standard", "ok", [])])
            self.assertTrue(all(all(v["exists"] for v in r["lanes"].values()) for r in rows))
            cfg = root / "composite-factory" / "factory.json"
            data = json.loads(cfg.read_text()); data["profile"] = "unknown"; cfg.write_text(json.dumps(data))
            bad = subprocess.run(["bash", str(BIN / "factory-doctor.sh"), "--factory", str(cfg.parent)], capture_output=True, text=True)
            self.assertNotEqual(bad.returncode, 0)
            self.assertIn("unknown factory profile", bad.stderr)


if __name__ == "__main__":
    unittest.main()
