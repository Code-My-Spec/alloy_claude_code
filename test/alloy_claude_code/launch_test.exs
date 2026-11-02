defmodule AlloyClaudeCode.LaunchTest do
  use ExUnit.Case, async: true

  alias AlloyClaudeCode.{Launch, OSProcess}

  @unix {:unix, :darwin}
  @win {:win32, :nt}

  @paths %{
    prompt_path: "/tmp/run/prompt.txt",
    stderr_path: "/tmp/run/stderr.txt",
    system_prompt_path: "/tmp/run/system_prompt.txt",
    workdir: "/work",
    config_dir: nil
  }

  @win_paths %{
    prompt_path: ~S(C:\Temp\run\prompt.txt),
    stderr_path: ~S(C:\Temp\run\stderr.txt),
    system_prompt_path: ~S(C:\Temp\run\system_prompt.txt),
    workdir: ~S(C:\work),
    config_dir: nil
  }

  describe "port_spec/5 on unix" do
    test "runs the shell command through /bin/sh, as before" do
      assert {:ok, {{:spawn_executable, "/bin/sh"}, opts}} =
               Launch.port_spec(@unix, "claude", ["-p", "it's"], @paths, [])

      assert opts == [
               {:args,
                [
                  "-lc",
                  "exec env  'claude' '-p' 'it'\"'\"'s' < '/tmp/run/prompt.txt' 2> '/tmp/run/stderr.txt'"
                ]},
               {:cd, "/work"},
               :binary,
               :exit_status,
               :use_stdio
             ]
    end

    test "names the config dir on the command line" do
      paths = %{@paths | config_dir: "/cfg"}

      assert {:ok, {_, [{:args, ["-lc", line]} | _]}} =
               Launch.port_spec(@unix, "c", [], paths, [])

      assert line =~ "exec env 'CLAUDE_CONFIG_DIR=/cfg' 'c'"
    end

    test "passes env through the port, never the command line" do
      env = [{"CLAUDE_CODE_OAUTH_TOKEN", "secret-value"}]
      assert {:ok, {_, opts}} = Launch.port_spec(@unix, "claude", [], @paths, env)
      assert {:env, [{~c"CLAUDE_CODE_OAUTH_TOKEN", ~c"secret-value"}]} in opts
      [{:args, ["-lc", line]} | _] = opts
      refute line =~ "secret-value"
    end
  end

  describe "port_spec/5 on Windows" do
    test "runs cmd.exe with the prompt on stdin and stderr in its file" do
      assert {:ok, {{:spawn, line}, opts}} =
               Launch.port_spec(
                 @win,
                 ~S(C:\Users\a b\.local\bin\claude.exe),
                 ["-p"],
                 @win_paths,
                 []
               )

      assert line ==
               ~S(cmd.exe /d /s /c ""C:\Users\a b\.local\bin\claude.exe" -p < "C:\Temp\run\prompt.txt" 2> "C:\Temp\run\stderr.txt"")

      assert opts == [{:cd, ~S(C:\work)}, :binary, :exit_status, :use_stdio]
    end

    test "sets the config dir and env through the port" do
      paths = %{@win_paths | config_dir: ~S(C:\cfg)}
      env = [{"CLAUDE_CODE_OAUTH_TOKEN", "secret-value"}]

      assert {:ok, {{:spawn, line}, opts}} = Launch.port_spec(@win, "claude", [], paths, env)

      assert {:env,
              [
                {~c"CLAUDE_CONFIG_DIR", ~c"C:\\cfg"},
                {~c"CLAUDE_CODE_OAUTH_TOKEN", ~c"secret-value"}
              ]} in opts

      refute line =~ "secret-value"
    end

    test "caret-escapes quoted JSON so cmd.exe passes it literally" do
      schema = ~s({"type":"object","enum":["a b"]})

      assert {:ok, line} = Launch.windows_command("claude", ["--json-schema", schema], @win_paths)

      assert line =~
               ~S(claude" --json-schema ^"{\^"type\^":\^"object\^",\^"enum\^":[\^"a b\^"]}^" <)
    end

    test "escapes every cmd.exe metacharacter" do
      assert Launch.caret_escape(~S{a&b|c<d>e^f%g!h(i)"j}) ==
               ~S{a^&b^|c^<d^>e^^f^%g^!h^(i^)^"j}
    end

    test "refuses a line break, which cmd.exe cannot carry" do
      assert {:error, message} = Launch.windows_command("claude", ["a\nb"], @win_paths)
      assert message =~ "line break"
    end
  end

  describe "argv_quote/1" do
    test "leaves a plain argument alone" do
      assert Launch.argv_quote("--model") == "--model"
    end

    test "quotes empty and spaced arguments" do
      assert Launch.argv_quote("") == ~s("")
      assert Launch.argv_quote("a b") == ~s("a b")
    end

    test "escapes quotes and the backslashes before them" do
      assert Launch.argv_quote(~S(say "hi")) == ~S("say \"hi\"")
      assert Launch.argv_quote(~S(a\"b c)) == ~S("a\\\"b c")
      assert Launch.argv_quote("dir\\ x\\") == ~s("dir\\ x\\\\")
    end
  end

  describe "file_args/3" do
    test "moves the system prompt to a file on Windows" do
      args = ["-p", "--append-system-prompt", "line one\nline two", "--model", "m"]

      assert Launch.file_args(@win, args, @win_paths) ==
               {[
                  "-p",
                  "--append-system-prompt-file",
                  ~S(C:\Temp\run\system_prompt.txt),
                  "--model",
                  "m"
                ], [{~S(C:\Temp\run\system_prompt.txt), "line one\nline two"}]}
    end

    test "leaves unix arguments alone" do
      args = ["--append-system-prompt", "line one\nline two"]
      assert Launch.file_args(@unix, args, @paths) == {args, []}
    end
  end

  describe "OSProcess.signal_command/3" do
    test "kills the process tree with taskkill on Windows" do
      assert OSProcess.signal_command(@win, 4242, "TERM") ==
               {"taskkill", ["/T", "/F", "/PID", "4242"], stderr_to_stdout: true}

      assert {"taskkill", ["/T", "/F", "/PID", "4242"], _} =
               OSProcess.signal_command(@win, 4242, "KILL")
    end

    test "signals the process group through sh on unix" do
      assert {"/bin/sh", ["-c", ~S(kill -s "$1" -- "-$2"), "alloy-kill", "KILL", "4242"], opts} =
               OSProcess.signal_command(@unix, 4242, "KILL")

      assert opts[:stderr_to_stdout]
      assert Enum.all?(opts[:env], fn {_name, value} -> is_nil(value) end)
    end
  end
end
