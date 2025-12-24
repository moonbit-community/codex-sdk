# Repo Examples for Parallel Subagents

Use these files as the canonical patterns for parallel and batch agent execution in this repo.

## cmd/real_world/add_docs/main.mbt

- Demonstrate `@async.with_task_group` with `@semaphore.Semaphore` to bound concurrency.
- Spawn one task per package and use `task_group.spawn_bg(allow_failure=true, fn() { ... })`.
- Use per-task working directories and capture failures without crashing the batch.

## cmd/real_world/review_mbti/processing.mbt

- Show a sliding-window concurrency pattern for many small jobs.
- Collect results into an array and emit progress per completion.

## cmd/real_world/review_mbti/README.md

- Document batch usage and concurrency knobs (`--concurrency`).
- Provide a detailed "How It Works" section that matches the processing flow.

## cmd/real_world/parallel_fix/agent.mbt

- Wrap Codex SDK usage in a helper `Agent` to centralize prompt, model, and options.
- Return `thread.id()` after runs to store session IDs for audit/debug.
- Override the Codex CLI path with `CodexOptions::new(codex_path_override=...)`.

## cmd/real_world/parallel_fix/main.mbt

- Orchestrate multi-repo work in parallel with bounded concurrency.
- Combine `task_group.spawn_bg` + `@semaphore.Semaphore` for parallelism control.

## README.md

- Provide the baseline SDK usage for creating `Codex`, `Thread`, and running a turn.
