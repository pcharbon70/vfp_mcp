defmodule VfpMcp.MixProject do
  use Mix.Project

  def project do
    [
      app: :vfp_mcp,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {VfpMcp.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Keep the MCP SDK behind VfpMcp.Server so the codec remains SDK-independent.
      {:ex_mcp, "== 1.0.0-rc.8"}
    ]
  end
end
