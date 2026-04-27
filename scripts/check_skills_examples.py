#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import subprocess
import sys


SKIP_DIRS = {".mooncakes", "target", "_build"}


def find_moon_projects(root: Path) -> list[Path]:
    """Find directories containing moon.mod.json, skipping excluded dirs."""
    projects = []
    for path in root.rglob("moon.mod.json"):
        if any(skip in path.parts for skip in SKIP_DIRS):
            continue
        projects.append(path.parent)
    return projects


def main() -> int:
    repo_root = Path(__file__).resolve().parents[1]
    skills_dir = repo_root / "skills"
    if not skills_dir.is_dir():
        print("No skills directory found.")
        return 1

    projects = find_moon_projects(skills_dir)
    if not projects:
        print("No moon projects found under skills/.")
        return 1

    errors: list[str] = []
    for project in sorted(projects):
        rel_path = project.relative_to(repo_root)
        result = subprocess.run(
            ["moon", "-C", str(project), "check"],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            errors.append(f"{rel_path}: moon check failed\n{result.stderr}")
        else:
            print(f"  {rel_path}")

    if errors:
        print("\nSkills examples check failed:")
        for error in errors:
            print(f"- {error}")
        return 1

    print(f"\nSkills examples check passed ({len(projects)} projects).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
