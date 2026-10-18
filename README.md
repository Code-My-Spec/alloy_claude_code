# AlloyClaudeCode

An [Alloy](https://github.com/alloy-ex/alloy) provider backed by the
[Claude Code](https://docs.claude.com/en/docs/claude-code) CLI. It runs
completions on a Claude subscription through `claude -p`, with Alloy's own
loop running the tools.

```elixir
{:alloy_claude_code, git: "https://github.com/Code-My-Spec/alloy_claude_code.git"}
```

```elixir
Alloy.stream("Summarise lib/", &IO.write/1,
  provider: {AlloyClaudeCode, %{model: "claude-sonnet-5", workdir: File.cwd!()}},
  tools: [Alloy.Tool.Core.Read]
)
```

- **Streams** the reply as Claude Code writes it (`stream-json` with partial
  messages), through `Alloy.stream/3` like any other provider.
- **Resumes** the CLI's own session when the transcript prefix it recorded
  still matches, so a turn sends only the new messages. Pass the run's
  `result.metadata.provider_state` back as `:provider_state` to continue
  across `Alloy.run/2` calls.
- **Runs no tools of its own.** Claude Code's built-in tools are off; every
  tool call comes back to Alloy.
- Stops a run that goes quiet for `:timeout_ms`, with `:max_run_ms` as the
  hard deadline.

See `AlloyClaudeCode` for every option.

Requires Alloy 0.13 and the `claude` CLI, logged in.

## Tests

```sh
mix ci                                   # format, credo, tests, dialyzer
mix test --include live_claude_cli       # against the real CLI
```
