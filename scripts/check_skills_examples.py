#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import sys


REQUIRED_FILES = ("moon.mod.json", "moon.pkg.json", "main.mbt", "README.md")
SKIP_DIRS = {".mooncakes", "target", ".git", "__pycache__"}


def validate_example(example_dir: Path, errors: list[str]) -> None:
    missing = [name for name in REQUIRED_FILES if not (example_dir / name).is_file()]
    if missing:
        errors.append(
            f"{example_dir}: missing {', '.join(missing)}"
        )
        return
    readme = (example_dir / "README.md").read_text(encoding="utf-8")
    if "moon run ." not in readme:
        errors.append(f"{example_dir}/README.md: missing 'moon run .'")


def main() -> int:
    repo_root = Path(__file__).resolve().parents[1]
    skills_dir = repo_root / "skills"
    if not skills_dir.is_dir():
        print("No skills directory found.")
        return 1

    errors: list[str] = []
    checked = 0
    for skill in skills_dir.iterdir():
        if not skill.is_dir():
            continue
        scripts_dir = skill / "scripts"
        if not scripts_dir.is_dir():
            continue
        for example in scripts_dir.iterdir():
            if not example.is_dir():
                continue
            if example.name in SKIP_DIRS or example.name.startswith("."):
                continue
            validate_example(example, errors)
            checked += 1

    if checked == 0:
        errors.append("No example directories found under skills/*/scripts.")

    if errors:
        print("Skills examples check failed:")
        for error in errors:
            print(f"- {error}")
        return 1

    print(f"Skills examples check passed ({checked} examples).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
