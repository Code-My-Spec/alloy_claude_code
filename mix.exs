defmodule AlloyClaudeCode.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/Code-My-Spec/alloy_claude_code"

  def project do
    [
      app: :alloy_claude_code,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      description: "An Alloy provider backed by the Claude Code CLI",
      source_url: @source_url,
      docs: [main: "AlloyClaudeCode", extras: ["README.md"]],
      dialyzer: [plt_add_apps: [:ex_unit]],
      package: [licenses: ["MIT"], links: %{"GitHub" => @source_url}]
    ]
  end

  def cli do
    [preferred_envs: [ci: :test]]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:alloy, "~> 0.13.0"},
      {:jason, "~> 1.2"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      ci: [
        "format --check-formatted",
        "deps.unlock --check-unused",
        "compile --warnings-as-errors --force",
        "credo --strict",
        "test",
        "dialyzer"
      ]
    ]
  end
end
