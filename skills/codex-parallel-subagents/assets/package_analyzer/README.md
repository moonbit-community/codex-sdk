# Package Analyzer

Summarize all MoonBit packages in a project by discovering `moon.pkg.json` files and analyzing each package's interface and source code.

## Run

```bash
moon run -C skills/codex-parallel-subagents/assets/package_analyzer skills/codex-parallel-subagents/assets/package_analyzer
```

Or with a custom working directory:
```bash
CODEX_WORKDIR=/path/to/project moon run -C skills/codex-parallel-subagents/assets/package_analyzer skills/codex-parallel-subagents/assets/package_analyzer
```

## What it does

1. Uses `find` to discover all directories containing `moon.pkg.json` (skips `.mooncakes`, `_build`, `target`)
2. For each package, reads `pkg.generated.mbti` (if available) and source files
3. Spawns a Codex thread per package to generate a summary (in parallel with bounded concurrency)
4. Uses a final Codex thread to create an overall project summary

## Environment variables

- `CODEX_WORKDIR` - Root directory to scan for packages (default: `.`)

## Output

- Individual package summaries based on interfaces and code
- An overall project summary combining all package insights
