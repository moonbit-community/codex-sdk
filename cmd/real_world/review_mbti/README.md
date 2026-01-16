# Review MBT Interface Files

Review MoonBit package interface files (`pkg.generated.mbti`) using the Codex SDK with intelligent grouping.

## Overview

This example demonstrates a **fan-out → sequential → fan-out** workflow pattern:

1. **Phase 1 (Fan-out)**: Parallel agents summarize each package
2. **Phase 2 (Sequential)**: Single planner groups related packages
3. **Phase 3 (Fan-out)**: Parallel agents review each group

## Workflow Pattern

```
Phase 1: Summarize (parallel)
┌──────────┐
│ pkg/a    │──▶ Summary A ──┐
│ pkg/b    │──▶ Summary B ──┼──▶ Phase 2: Plan (sequential)
│ pkg/c    │──▶ Summary C ──┤         │
│ pkg/d    │──▶ Summary D ──┘         ▼
└──────────┘              ┌─────────────────┐
                          │ Planner groups  │
                          │ related packages│
                          └────────┬────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              ▼                    ▼                    ▼
Phase 3: Review (parallel)
       ┌─────────┐          ┌─────────┐          ┌─────────┐
       │ Group 1 │          │ Group 2 │          │ Group 3 │
       │ map,    │          │ array,  │          │ string, │
       │ hashmap │          │ vector  │          │ bytes   │
       └─────────┘          └─────────┘          └─────────┘
```

This pattern ensures related packages (like `map`, `sortedmap`, `hashmap`) are reviewed together for API consistency.

## Usage

```bash
moon run cmd/real_world/review_mbti -- [OPTIONS] <path>
```

### Arguments

| Argument | Description |
|----------|-------------|
| `<path>` | Path to the MoonBit module root |

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `-c, --concurrency <num>` | Number of parallel agents | 5 |
| `-v, --verbose` | Show detailed progress | Off |
| `-o, --output <dir>` | Output directory for reviews | `mbti-reviews` |
| `-p, --prompt <text>` | Custom focus for the review | None |
| `-h, --help` | Print help message | |

### Environment Variables

| Variable | Description |
|----------|-------------|
| `REVIEW_MBTI_CONCURRENCY` | Override `--concurrency` |
| `REVIEW_MBTI_OUTPUT` | Override `--output` |
| `REVIEW_MBTI_VERBOSE` | Override `--verbose` (1/true/yes/on) |
| `REVIEW_MBTI_PROMPT` | Override `--prompt` |

### Examples

```bash
# Review all packages in current directory
moon run cmd/real_world/review_mbti -- .

# Review with custom focus
moon run cmd/real_world/review_mbti -- -p "Focus on error handling patterns" .

# Higher concurrency with verbose output
moon run cmd/real_world/review_mbti -- -c 8 -v /path/to/moonbit-core
```

## How It Works

### Phase 1: Summarize

Each package is summarized by an independent agent:

```moonbit
let summaries = @shared.for_all_tasks(
  config.files,
  async fn(idx, _) {
    let handle = config.summarize_start(idx)
    // ... retry with handle.prompt(), validate, finish
  },
  parallelism=config.concurrency,
)
```

The `SummarizeHandle` caches file content at setup to avoid re-reading on retry.

### Phase 2: Plan

A single planner agent receives all summaries and groups related packages:

```moonbit
let plan_handle = config.plan_start(summaries)
let groups = try {
  let thread = codex.start_thread(...)
  @async.retry(fn() {
    let prompt = plan_handle.prompt()
    let response = thread.run(prompt)
    plan_handle.validate(response.final_response)  // Parses JSON, validates coverage
  }, max_retry=3)
} catch { ... }
```

The planner:
- Groups related packages (map variants, array variants, etc.)
- Aims for 3-5 packages per group
- May place a package in multiple groups if it fits multiple categories
- Must cover all packages (validation enforces this)

### Phase 3: Review

Each group is reviewed by an independent agent:

```moonbit
let reviews = @shared.for_all_tasks(
  groups,
  async fn(idx, group) {
    let handle = config.review_start(idx, group)
    // ... retry with handle.prompt(), validate, finish
  },
  parallelism=config.concurrency,
)
```

Reviews focus on API consistency across related packages. If a custom prompt is provided via `-p`, it's included in the review context.

## Output Format

Reviews are saved as Markdown files in the output directory:

```
mbti-reviews/
├── map_variants.review.md
├── array_collections.review.md
└── string_utilities.review.md
```

Each file contains:
- Group name and packages
- API consistency assessment
- Issues and inconsistencies
- Suggestions for improvement

## Project Structure

```
review_mbti/
├── main.mbt           # Entry point, 3-phase orchestration
├── app/
│   ├── job.mbt        # Handle types for all 3 phases
│   ├── types.mbt      # PackageSummary, PackageGroup, GroupReview
│   ├── args.mbt       # CLI argument parsing
│   ├── task.mbt       # File resolution helpers
│   └── io_utils.mbt   # File discovery, mkdir
```

## Handle Types

Each phase has its own handle type with consistent lifecycle:

| Handle | Phase | Key Methods |
|--------|-------|-------------|
| `SummarizeHandle` | 1 | `prompt()`, `validate()`, `finish()`, `error()` |
| `PlanHandle` | 2 | `prompt()`, `validate()`, `finish()`, `error()` |
| `ReviewHandle` | 3 | `prompt()`, `validate()`, `finish()`, `error()` |

All handles:
- Track attempt count for retry-aware prompts
- Store `last_error` for error context in retries
- Cache content at setup (not on each prompt)

## Dependencies

- `@codex` - Codex SDK for AI agents
- `@async` - Task groups, retry, semaphore
- `@fs` - File system operations
- `@args` - CLI argument parsing
- `@json` - JSON parsing for planner output

## Key Concepts for SDK Users

1. **Dynamic fan-out**: Phase 3 task count depends on Phase 2 output
2. **Retry with error context**: Failed attempts inform retry prompts
3. **Validation with structured output**: Parse AI responses as JSON
4. **Content caching**: Read files once at setup, not on each retry
5. **Custom prompts**: User-provided focus passed to review agents
