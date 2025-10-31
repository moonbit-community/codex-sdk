# Review MBT Interface Files

A MoonBit tool to batch review MoonBit package interface files (`pkg.generated.mbti`) using the Codex SDK. This tool automatically generates API design feedback and saves results as Markdown files.

## Features

- **Flexible Target Selection**: Review all files, only changed files, or specific files
- **Concurrent Execution**: Control parallel processing with configurable concurrency
- **Robust Error Handling**: Individual failures don't affect the overall process
- **Structured Output**: One Markdown file per package with standardized naming
- **Progress Tracking**: Real-time status updates and completion indicators

## Usage

```bash
moon run cmd/real_world/review_mbti -- [OPTIONS] <PROJECT_PATH>
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--all` | Review all `pkg.generated.mbti` files | Implicit when no other filter is specified |
| `--changed` | Only review files changed relative to `HEAD` | Off |
| `--files=<list>` | Review specific comma-separated file paths | None |
| `--concurrency=<N>` | Maximum number of concurrent reviews | 5 |
| `--verbose` | Show detailed progress for each file | Off |

### Examples

#### Review all files in the current directory
```bash
moon run cmd/real_world/review_mbti -- .
```

#### Review only changed files
```bash
moon run cmd/real_world/review_mbti -- --changed --concurrency=3 .
```

#### Review specific files
```bash
moon run cmd/real_world/review_mbti -- --files=bytes/pkg.generated.mbti,string/pkg.generated.mbti .
```

#### Full-scale review with higher concurrency
```bash
moon run cmd/real_world/review_mbti -- --all --concurrency=8 --verbose /path/to/project
```

## How It Works

1. **File Discovery**: Scans the project directory recursively to find all `pkg.generated.mbti` files (skipping `node_modules`, `target`, and hidden directories)
2. **Filtering**: Applies selection criteria based on `--files`, `--changed`, or `--all`
3. **Concurrent Processing**: Uses a semaphore to limit concurrent Codex API calls
4. **Review Generation**: For each file:
   - Reads the interface content
   - Extracts the package name
   - Sends a review prompt to Codex
   - Receives structured feedback
5. **Output Persistence**: Saves each review as a Markdown file in `scripts/output/`
6. **Summary Report**: Displays overall statistics including successes, failures, and timing

## Output Format

### File Naming
Reviews are saved with a standardized naming convention:
- `bytes/pkg.generated.mbti` → `bytes.review.md`
- `immut/array/pkg.generated.mbti` → `immut_array.review.md`

### Markdown Template
```markdown
# Review: <package_name>

**File:** `<relative_path>`  
**Status:** ✓ Success | ✗ Failed

---
<review_content_or_error>
```

## Review Prompt

The tool uses the following prompt template for each review:

```
Review this MoonBit package interface file (<relative_path>):

```moonbit
<file_content>
```

Please provide:
1. A brief assessment of the API design
2. Any potential issues or inconsistencies
3. Suggestions for improvement (if any)

Keep the review concise and focused on the public API surface.
```

## Implementation Details

### Core Functions

| Function | Purpose |
|----------|---------|
| `find_mbti_files` | Recursively discovers all interface files |
| `get_changed_mbti_files` | Filters files based on git diff |
| `review_mbti_file` | Performs a single file review |
| `save_review_to_file` | Persists review results as Markdown |
| `process_concurrently` | Manages concurrent execution with semaphore |
| `main` | Orchestrates the entire workflow |

### Concurrency Control

Uses a "sliding window" approach with `@async.with_task_group` and `@semaphore.Semaphore`:
- Spawns background tasks for each file
- Semaphore ensures at most `N` concurrent reviews
- Tasks automatically release resources upon completion

### Error Handling

- Failed reviews still generate output files for easy identification
- Individual file errors don't halt the entire process
- Progress indicators use ✓/✗ symbols for quick status overview

## Dependencies

- `@codex` - Codex SDK for AI-powered reviews
- `@async` - Asynchronous task execution
- `@fs` - File system operations
- `@process` - Git command execution
- `@clap` - CLI argument parsing
- `@semaphore` - Concurrency control

## Tips

- **Small changes**: Use `--changed --concurrency=3` for PRs
- **Single package iteration**: Use `--files=pkg/path/pkg.generated.mbti`
- **Full quality audit**: Use `--all --concurrency=5`
- **Find issues**: After running, search output with `grep -r "issue" scripts/output/`

## Limitations

- Output quality depends on the Codex model
- High concurrency (>10) may trigger API rate limits
- Fixed prompt template (no customization yet)
- No automatic retry mechanism for failed reviews

## Comparison with JavaScript Version

This MoonBit implementation provides:
- Native integration with MoonBit tooling
- Type-safe concurrent execution
- Structured error handling with MoonBit's error system
- Direct access to file system APIs without Node.js overhead

## Future Enhancements

- [ ] Add `--retry-failed` flag for automatic retries
- [ ] Generate JSON summary with `--summary-json`
- [ ] Support `--mode=quick|deep` for different prompt strategies
- [ ] Implement rate limiting with token bucket algorithm
- [ ] Add timeout handling for long-running reviews
- [ ] Integrate with GitHub PRs for automatic comment generation
