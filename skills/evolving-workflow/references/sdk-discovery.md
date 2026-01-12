# SDK discovery (don’t memorize primitives)

Prefer `moon doc` / `moon ide` over guessing APIs.

## API discovery (packages, types, methods)

- List packages: `moon doc ''`
- Explore a package: `moon doc "@peter-jerry-ye/codex"` (or the relevant package path)
- Lookup a type/value/method: `moon doc "ThreadOptions"`, `moon doc "ThreadOptions::new"`
- Wildcards: `moon doc "ThreadOptions::*"`

## Code navigation (project-local)

- Find definitions: `moon ide peek-def <Symbol>`
- Scan symbols: `moon ide outline <dir-or-file>`
- Find uses: `moon ide find-references <Symbol>`

## Workflow authoring loop

When you change MoonBit code in a repo, a common workflow is:

- `moon fmt`
- `moon info`
- `moon test`
- `moon check`

In a plan-as-code workflow:

- Treat `moon fmt` / `moon info` as required maintenance steps (style + interface generation).
- Treat `moon test` / `moon check` as verifications (they decide pass/fail).
- After `moon info`, consider reviewing `pkg.generated.mbti` diffs.
