# Troubleshooting Parallel Subagents

## Common failure modes and quick fixes

### Session permissions

**Symptom**: Codex fails with permission denied errors.

**Fix**: Ensure your Codex CLI has access to the working directory:
```moonbit
ThreadOptions::new(working_directory="/path/to/repo")
```
Verify the path exists before starting the thread.

### Sandbox constraints

**Symptom**: File reads/writes are blocked.

**Fix**: Bump to a less restrictive sandbox mode:
```moonbit
ThreadOptions::new(sandbox_mode=@codex.SandboxMode::WorkspaceWrite)
// or for full access:
ThreadOptions::new(sandbox_mode=@codex.SandboxMode::DangerFullAccess)
```

### Missing CLI binary

**Symptom**: Codex command not found.

**Fix**: Set the CLI path explicitly:
```moonbit
CodexOptions::new(codex_path_override="/path/to/codex")
```

### API configuration

**Symptom**: Authentication errors or API failures.

**Fix**: Verify your API key and provider settings:
- Set `OPENAI_API_KEY` or your provider's key in environment
- Check `base_url` settings if using a custom endpoint

### Model errors

**Symptom**: Model not found or rate limit errors.

**Fix**:
- Double-check model names (e.g., `anthropic/claude-sonnet-4`)
- Rate-limit your batch with a semaphore:
```moonbit
let semaphore = @semaphore.Semaphore::new(2)  // max 2 concurrent
```

## Dependency issues

### Adding packages

When you need `peter-jerry-ye/codex` or other modules:
```bash
moon add peter-jerry-ye/codex
moon add moonbitlang/x
```

### Version conflicts

MoonBit resolves dependencies with MVS. If you hit conflicts, try pinning a version:
```bash
moon add pkg@0.1.1
```

### Build errors

If you see build errors in `moonbitlang/x` or `moonbitlang/async`:
1. Run `moon upgrade` to update your toolchain
2. Align your toolchain with the versions required by `peter-jerry-ye/codex`
