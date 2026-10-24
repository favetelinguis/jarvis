defmodule Jarvis.AgentScriptsTest do
  use ExUnit.Case, async: true

  @tag timeout: 60_000
  test "the shared MCP server and harness lifecycle adapters pass their protocol tests" do
    {output, status} =
      System.cmd("node", ["--test", "test/agent/integration.test.mjs"], stderr_to_stdout: true)

    assert status == 0, output
  end
end
