#!/usr/bin/env python3
"""Normalize supported factory layouts for the registry and doctor.

The standard profile is the original lanes/release-directory contract. A
composite factory declares its framework lanes and archive root explicitly.
Unknown profiles are errors, never silently treated as missing lanes.
"""
import json
import os
from pathlib import Path
import sys


def resolve(root, raw):
    if not isinstance(raw, str) or not raw:
        return None
    path = Path(os.path.expanduser(raw))
    return str(path if path.is_absolute() else root / path)


def normalize(root):
    data = json.loads((root / "factory.json").read_text())
    profile = data.get("profile", "standard")
    if profile not in ("standard", "composite"):
        raise ValueError(f"unknown factory profile: {profile}")
    if profile == "standard":
        lanes = data.get("lanes", {})
        releases = "releases"
        project = data.get("project", "")
        test = data.get("commands", {}).get("test", "")
    else:
        lanes = data.get("framework", {})
        releases = data.get("releases", {}).get("root", "")
        project = data.get("obeya", {}).get("project", data.get("project", ""))
        test = data.get("commands", {}).get("test", "")
    if not isinstance(lanes, dict):
        raise ValueError(f"{profile} lanes must be an object")
    return {"profile": profile, "project": project,
            "lanes": {name: resolve(root, lanes.get(name)) for name in ("dev", "next", "live")},
            "releases": resolve(root, releases), "test": test,
            "distribution": bool(data.get("distribution"))}


if __name__ == "__main__":
    try:
        print(json.dumps(normalize(Path(sys.argv[1]).resolve())))
    except (OSError, ValueError, TypeError, KeyError) as error:
        print(f"factory-profile: {error}", file=sys.stderr)
        sys.exit(2)
