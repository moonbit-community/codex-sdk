# Fix Warnings Example

Automated workflow to fix compilation warnings in a MoonBit project using Codex SDK.

## Overview

This example demonstrates how to:
1. Clone a repository
2. Create a new branch
3. Run `moon check` to find warnings
4. Use AI to fix warnings iteratively
5. Verify with `moon check` and `moon test`
6. Format code and update interface files
7. Commit and push changes
8. Clean up temporary directory

## Usage

### Show help

```bash
moon run example_fix_warnings -- --help
```

### Dry run (show what would be done)

```bash
moon run example_fix_warnings -- --dry-run
```

### Run with default settings

```bash
moon run example_fix_warnings --
```

### Run with custom parameters

```bash
moon run example_fix_warnings -- \
  --repo-url https://github.com/your-org/your-repo.git \
  --clone-path /tmp/my-fix-warnings \
  --branch-name fix/warnings-custom \
  --max-iterations 10
```

## Parameters

- `--repo-url <URL>` - Repository URL to clone (default: codex-sdk)
- `--clone-path <PATH>` - Local directory for cloning (default: /tmp/moonbit-fix-warnings)
- `--branch-name <NAME>` - Branch name for fixes (default: fix/warnings-auto)
- `--max-iterations <N>` - Maximum fix iterations (default: 5)
- `--dry-run` - Show workflow steps without executing
- `-h, --help` - Show help message

## How It Works

The workflow:

1. **Clone** - Clones the repository to a temporary directory
2. **Branch** - Creates and checks out a new branch
3. **Detect** - Runs `moon check` to find all warnings and errors
4. **Fix** - Uses Codex AI agent to fix issues iteratively
5. **Verify** - Runs `moon check` after each iteration to track progress
6. **Test** - Runs `moon test` to ensure no regressions
7. **Format** - Runs `moon info` and `moon fmt` to update interfaces
8. **Review** - Shows git diff of changes
9. **Commit** - Commits changes with descriptive message
10. **Push** - Pushes branch to remote
11. **Cleanup** - Removes temporary directory

## Example Output

```
=== MoonBit Warning Fixer ===

Configuration:
  Repository URL: https://github.com/moonbit-community/codex-sdk.git
  Clone path: /tmp/moonbit-fix-warnings
  Branch name: fix/warnings-auto
  Max iterations: 5
  Dry run: false

🚀 Starting workflow...

Step 1: Cloning repository...
✓ Repository cloned to /tmp/moonbit-fix-warnings

Step 2: Creating branch 'fix/warnings-auto'...
✓ Branch created and checked out

Step 3: Discovering MoonBit project...
✓ Found project: codex-sdk

Step 4: Running moon check to find warnings...
Found 0 errors and 3 warnings

Warnings to fix:
  - src/foo.mbt:42: Unused variable 'x'
  - src/bar.mbt:15: Deprecated function usage
  - src/baz.mbt:88: Missing documentation

...
```

## Notes

- The workflow uses a temporary directory and cleans up after itself
- All changes are made on a new branch - the original repository is not affected
- The AI agent has write access to the cloned repository
- Use `--dry-run` to preview the workflow without making changes
