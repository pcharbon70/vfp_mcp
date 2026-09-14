ExUnit.start()

# specled covers:
# - vfp_mcp.boundary.development_isolation
# - vfp_mcp.boundary.no_vfp_execution

workspace_root = Path.expand("..", __DIR__)
temporary_root = Path.join(System.tmp_dir!(), "vfp_mcp_tests")

isolation_policy =
  VfpMcp.Development.IsolationPolicy.new(workspace_root,
    disposable_roots: [temporary_root, ".vfp_mcp/test-work"]
  )

Application.put_env(:vfp_mcp, :test_isolation_policy, isolation_policy)

if source_root = System.get_env("VFP_MCP_TEST_SOURCE_ROOT") do
  case VfpMcp.Development.IsolationPolicy.authorize(
         isolation_policy,
         :committed_fixture,
         source_root
       ) do
    :ok -> :ok
    {:error, reason} -> raise "unsafe VFP_MCP_TEST_SOURCE_ROOT: #{inspect(reason)}"
  end
end
