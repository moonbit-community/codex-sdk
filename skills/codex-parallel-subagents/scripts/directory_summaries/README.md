# Directory Summaries Example

Run:

```bash
moon run .
```

Notes:

- Set `CODEX_WORKDIR` to point at the repo root you want summarized.
- Each file is read, summarized by a subagent, then the tree and full repo are summarized.
- For large trees, consider adding a completion log and `limit`/`offset` style slicing so you can restart mid-run after interruptions.
