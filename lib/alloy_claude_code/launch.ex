defmodule AlloyClaudeCode.Launch do
  @moduledoc false
  # How the CLI is started, per OS. Pure: the OS is an argument, so both
  # branches are tested on any host.
  #
  # Both feed the prompt file to stdin (`claude -p` reads it to EOF, which a
  # port cannot send) and send stderr to a file, so stdout carries nothing but
  # stream-json. On unix /bin/sh wires the redirects; on Windows cmd.exe does,
  # which also runs a `.cmd` shim (npm's install) and resolves a bare name
  # through PATHEXT.

  @type os_type :: {:unix | :win32, atom()}
  @type paths :: %{
          required(:prompt_path) => String.t(),
          required(:stderr_path) => String.t(),
          required(:workdir) => String.t(),
          optional(:config_dir) => String.t() | nil,
          optional(:system_prompt_path) => String.t()
        }

  @doc """
  The `Port.open/2` name and options that run `executable` with `args`.
  `env` reaches the CLI through the port, never the command line.
  """
  @spec port_spec(os_type(), String.t(), [String.t()], paths(), [{String.t(), String.t()}]) ::
          {:ok, {term(), list()}} | {:error, String.t()}
  def port_spec({:win32, _}, executable, args, paths, env) do
    with {:ok, line} <- windows_command(executable, args, paths) do
      env = [{"CLAUDE_CONFIG_DIR", Map.get(paths, :config_dir)} | env]
      # `:hide` gives the child a hidden console. Without one, claude.exe
      # writes nothing at all (not even to a redirected file) and a full run
      # exits 1, so every turn under a Windows service failed with no output.
      {:ok, {{:spawn, line}, base_opts(paths) ++ [:hide] ++ env_opt(env)}}
    end
  end

  def port_spec({:unix, _}, executable, args, paths, env) do
    {:ok,
     {{:spawn_executable, "/bin/sh"},
      [{:args, ["-lc", unix_command(executable, args, paths)]} | base_opts(paths)] ++
        env_opt(env)}}
  end

  defp base_opts(paths), do: [{:cd, paths.workdir}, :binary, :exit_status, :use_stdio]

  defp env_opt(env) do
    case Enum.reject(env, fn {_key, value} -> is_nil(value) end) do
      [] -> []
      env -> [{:env, Enum.map(env, fn {key, value} -> {~c"#{key}", ~c"#{value}"} end)}]
    end
  end

  @doc """
  Windows only: arguments too free-form for a cmd.exe line go in files.
  Returns the rewritten args and the files to write first.
  """
  @spec file_args(os_type(), [String.t()], paths()) ::
          {[String.t()], [{String.t(), String.t()}]}
  def file_args({:win32, _}, args, paths), do: file_args(args, paths, [], [])
  def file_args({:unix, _}, args, _paths), do: {args, []}

  defp file_args(["--append-system-prompt", prompt | rest], paths, acc, files) do
    path = paths.system_prompt_path
    file_args(rest, paths, [path, "--append-system-prompt-file" | acc], [{path, prompt} | files])
  end

  defp file_args([arg | rest], paths, acc, files), do: file_args(rest, paths, [arg | acc], files)
  defp file_args([], _paths, acc, files), do: {Enum.reverse(acc), Enum.reverse(files)}

  # `exec env ... claude ...` makes the shell replace itself with env, which
  # replaces itself with claude, so the port's OS pid is claude's own.
  @doc false
  @spec unix_command(String.t(), [String.t()], paths()) :: String.t()
  def unix_command(executable, args, paths) do
    env_args =
      [{"CLAUDE_CONFIG_DIR", Map.get(paths, :config_dir)}]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Enum.map_join(" ", fn {key, value} -> shell_escape("#{key}=#{value}") end)

    "exec env " <>
      env_args <>
      " " <>
      Enum.map_join([executable | args], " ", &shell_escape/1) <>
      " < " <>
      shell_escape(paths.prompt_path) <>
      " 2> " <>
      shell_escape(paths.stderr_path)
  end

  defp shell_escape(value) when is_binary(value) do
    "'" <> String.replace(value, "'", "'\"'\"'") <> "'"
  end

  # Each argument is quoted for the program's own argv parser, then every
  # cmd.exe metacharacter is caret-escaped, so cmd passes it through literally
  # and never enters quote mode. The executable and the redirect targets are
  # plainly quoted: cmd must read them, and paths hold no quotes. `/s` strips
  # only the outermost pair. A line break ends a cmd.exe line and cannot be
  # escaped, so it is refused rather than truncating the command.
  @doc false
  @spec windows_command(String.t(), [String.t()], paths()) ::
          {:ok, String.t()} | {:error, String.t()}
  def windows_command(executable, args, paths) do
    case Enum.find([executable | args], &String.contains?(&1, ["\n", "\r"])) do
      nil ->
        line =
          Enum.join(
            [quote_path(executable) | Enum.map(args, &(&1 |> argv_quote() |> caret_escape()))],
            " "
          )

        {:ok,
         ~s(cmd.exe /d /s /c ") <>
           line <>
           " < " <>
           quote_path(paths.prompt_path) <> " 2> " <> quote_path(paths.stderr_path) <> ~s(")}

      arg ->
        {:error,
         "claude argument cannot pass through cmd.exe, it holds a line break: " <>
           String.slice(arg, 0, 80)}
    end
  end

  defp quote_path(path), do: ~s(") <> path <> ~s(")

  # The MSVCRT rules: backslashes are literal unless they precede a quote,
  # where each is doubled and the quote escaped; trailing ones are doubled
  # before the closing quote.
  @doc false
  @spec argv_quote(String.t()) :: String.t()
  def argv_quote(""), do: ~s("")

  def argv_quote(arg) do
    if String.contains?(arg, [" ", "\t", "\v", "\""]) do
      quoted =
        Regex.replace(~r/(\\*)("|$)/, arg, fn _all, slashes, tail ->
          doubled = slashes <> slashes
          if tail == "\"", do: doubled <> "\\\"", else: doubled
        end)

      ~s(") <> quoted <> ~s(")
    else
      arg
    end
  end

  @doc false
  @spec caret_escape(String.t()) :: String.t()
  def caret_escape(text), do: Regex.replace(~r/[()%!^"<>&|]/, text, "^\\0")
end
