# spec/mcp_server_spec.cr
require "./spec_helper"
require "crystal-mcp"
require "../src/mcp_server"

private def make_mcp_pair : Tuple(MCP::Server, MCP::Session, MCP::Client)
  srv_in, cli_out = IO.pipe
  cli_in, srv_out = IO.pipe
  server = TsEdit::McpServer.build
  session = server.open_session(MCP::IOTransport.new(srv_in, srv_out))
  client = MCP::Client.new(MCP::IOTransport.new(cli_in, cli_out),
    MCP::Implementation.new(name: "spec-client", version: "0.0.1"))
  client.start
  {server, session, client}
end

describe "ts-edit MCP server" do
  it "lists all 16 tools" do
    server, _session, client = make_mcp_pair
    names = client.list_all_tools.map(&.name).sort
    names.should eq %w[ts_close ts_diff ts_edit ts_expect ts_find ts_languages ts_node_at
      ts_open ts_open_source ts_outline ts_preview ts_recipes ts_redo ts_source ts_undo ts_write]
    client.close
    server.close
  end

  it "drives an open/find/edit/source session" do
    server, _session, client = make_mcp_pair
    py = "def greet(name):\n    return name\n\ndef shout(name):\n    return greet(name).upper()\n"

    opened = client.call_tool("ts_open_source", arguments: {source: py, language: "python"})
    opened.error?.should be_false
    sid = JSON.parse(opened.text)["session"].as_s

    found = client.call_tool("ts_find", arguments: {session: sid, query: "(function_definition name: (identifier) @n)"})
    JSON.parse(found.text)["matches"].as_a.size.should eq 2

    edited = client.call_tool("ts_edit", arguments: {
      session: sid, op: "replace", capture: "n", replacement: "welcome",
      query: "((function_definition name: (identifier) @n) (#eq? @n \"greet\"))",
    })
    edited.error?.should be_false
    JSON.parse(edited.text)["source_changed"].as_bool.should be_true

    source = client.call_tool("ts_source", arguments: {session: sid})
    JSON.parse(source.text)["source"].as_s.should contain "def welcome(name):"

    client.close
    server.close
  end

  it "reports tool-level errors as is_error results" do
    server, _session, client = make_mcp_pair
    result = client.call_tool("ts_edit", arguments: {
      session: "nope", op: "replace", query: "(identifier) @i", capture: "i", replacement: "x",
    })
    result.error?.should be_true
    JSON.parse(result.text)["message"].as_s.should contain "unknown session"
    client.close
    server.close
  end
end
