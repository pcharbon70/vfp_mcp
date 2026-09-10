defmodule VfpMcp.MixProject do
  use Mix.Project

  # covers: vfp_mcp.package.elixir_otp_runtime
  # covers: vfp_mcp.package.dependency_boundaries
  # covers: vfp_mcp.protocol.sdk_boundary

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
      {:ex_mcp, "== 1.0.0-rc.8"},
      # cowlib 2.19.0 is affected by CVE-2026-43969 and CVE-2026-43971.
      # Pin the transitive dependency to the upstream commit containing the
      # security fixes until a fixed Hex release is published.
      {:cowlib,
       git: "https://github.com/ninenines/cowlib.git",
       ref: "89da27ee4c241f5d649ba7d9b7f2188918af6cea",
       override: true},
      {:spec_led_ex,
       github: "specleddev/specled_ex",
       ref: "301fad7cd490ea7328d47ec2f46c3d3f0c20a225",
       only: [:dev, :test],
       runtime: false}
    ]
  end
end
