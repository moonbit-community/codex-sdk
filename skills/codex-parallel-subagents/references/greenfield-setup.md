# Greenfield Setup: Parallel Book Summaries

This walk-through starts from a new MoonBit module, adds the Codex SDK, and runs a parallel batch that summarizes a list of books.

## 1) Create a new module

```bash
moon new my_module --name my_module --user your_user
cd my_module
```

Note: MoonBit module names must be alphanumeric or underscore.

## 2) Add the Codex SDK dependency

Preferred:

```bash
moon update
moon add peter-jerry-ye/codex
moon add moonbitlang/x
```

If `moon add` fails (network or toolchain issues), edit `cmd/main/moon.pkg.json` manually.
Replace the imports with this shape (keep your module name):

```json
{
  "is-main": true,
  "import": [
    { "path": "your_user/my_module", "alias": "lib" },
    "peter-jerry-ye/codex",
    "moonbitlang/async",
    "moonbitlang/async/semaphore",
    "moonbitlang/async/stdio",
    "moonbitlang/x/sys"
  ]
}
```

If you want to put Codex helpers in your library package (`my_module.mbt`),
also add the same imports to the top-level `moon.pkg.json`.

## 2b) Ensure native target

The Codex SDK runs the `codex` CLI, so it requires native builds. Add this to `moon.mod.json`:

```json
{
  "preferred-target": "native"
}
```

## 3) Write the parallel batch example

Edit `cmd/main/main.mbt`:

```moonbit
struct Book {
  title : String
  author : String
}

async fn summarize_book(codex : @codex.Codex, book : Book) -> String {
  let prompt =
    #|Summarize the following book in 3 bullet points, then give a 1-sentence hook.
    $|Title: \{book.title}
    $|Author: \{book.author}
  let thread = codex.start_thread(
    options=@codex.ThreadOptions::new(
      model?=@sys.get_env_vars().get("MODEL"),
    ),
  )
  let turn = thread.run(prompt) catch {
    e => return "error: \{e}"
  }
  return turn.final_response
}

async fn main {
  let books : Array[Book] = [
    { title: "Dune", author: "Frank Herbert" },
    { title: "The Left Hand of Darkness", author: "Ursula K. Le Guin" },
    { title: "Neuromancer", author: "William Gibson" },
    { title: "Piranesi", author: "Susanna Clarke" }
  ]
  let codex = @codex.Codex::new()
  let results : Array[String] = []
  let parallelism = 2
  @async.with_task_group(fn(task_group) {
    let semaphore = @semaphore.Semaphore::new(parallelism)
    for book in books {
      task_group.spawn_bg(allow_failure=true, fn() {
        semaphore.acquire()
        defer semaphore.release()
        let summary = summarize_book(codex, book) catch {
          e => "error: \{e}"
        }
        results.push("# \{book.title}\n\{summary}\n")
      })
    }
  })
  for item in results {
    @stdio.stdout.write("\{item}\n")
  }
}
```

Notes:
- `async fn main` is required because Codex calls are async.
- Create a new `Thread` per book; do not reuse a single thread concurrently.
- Use a semaphore to bound concurrency and reduce rate-limit risk.
- Set `MODEL` if you need a specific model; otherwise the CLI default applies.

## 4) Run it

```bash
moon run cmd/main
```

Ensure the Codex CLI is installed and configured (API key, base URL if needed).

## Troubleshooting

- If you see build errors in `moonbitlang/x` or `moonbitlang/async`, your Moon toolchain may be incompatible with the dependency versions. Run `moon upgrade` or align your toolchain with the versions required by `peter-jerry-ye/codex`.
- If Codex fails with `permission denied` for `~/.codex/sessions`, fix ownership (for example: `sudo chown -R $(whoami) ~/.codex`).
