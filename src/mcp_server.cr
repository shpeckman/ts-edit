# src/mcp_server.cr
require "crystal-mcp"
require "./ts-edit/dispatcher"

module TsEdit::McpServer
  extend self

  INSTRUCTIONS = "ts-edit performs syntax-aware source edits through tree-sitter queries. " \
                 "Typical loop: ts_open or ts_open_source to start a session, ts_outline/ts_find/ts_node_at to locate targets, " \
                 "ts_preview to test an edit, ts_edit to apply it, ts_expect/ts_diff to verify, ts_write to persist."

  SESSION_SCHEMA = {
    type:       "object",
    properties: {session: {type: "string", description: "session id returned by ts_open/ts_open_source"}},
    required:   ["session"],
  }

  EDIT_SCHEMA = {
    type:       "object",
    properties: {
      session: {type: "string", description: "session id returned by ts_open/ts_open_source"},
      op: {type: "string", description: "replace|delete|insert|wrap|swap|move|reorder|sort|dedupe|unwrap|overwrite|duplicate|extract|comment|uncomment|indent|outdent|toggle|rename"},
      query: {type: "string", description: "tree-sitter query source"},
      capture: {description: "capture name (string) or capture names (array of strings)"},
      within: {type: "string", description: "scope query; the main query runs inside each scope match's first capture"},
      skip: {type: "integer"}, limit: {type: "integer"}, check: {type: "boolean"},
      before: {type: "boolean"}, position: {type: "string", description: "before|after"},
      prefix: {type: "string"}, suffix: {type: "string"}, replacement: {type: "string"}, text: {type: "string"},
      first: {type: "string"}, second: {type: "string"}, a: {type: "string"}, b: {type: "string"},
      outer: {type: "string"}, inner: {type: "string"}, from: {type: "string"},
      to: {type: "string"}, to_query: {type: "string"}, to_capture: {type: "string"},
      target: {type: "string"}, source_capture: {type: "string"}, by: {type: "integer"},
      scope: {description: "rename scope node types (array of strings)"},
      reverse: {type: "boolean"},
    },
    required: ["session", "op", "query"],
  }

  def build(dispatcher : Dispatcher = Dispatcher.new) : MCP::Server
    server = MCP::Server.new(
      MCP::Implementation.new(name: "ts-edit", version: TsEdit::VERSION),
      instructions: INSTRUCTIONS)
    register(server, dispatcher)
    server
  end

  def run : Nil
    build.run_stdio
  end

  def register(server : MCP::Server, dispatcher : Dispatcher) : Nil
    server.tool("ts_open", description: "Open a file into a new editing session",
      input_schema: {
        type:       "object",
        properties: {
          path:     {type: "string", description: "file path to open"},
          language: {type: "string", description: "language name (inferred from the extension when omitted)"},
          check:    {type: "boolean", description: "reject sources with syntax errors (default true)"},
        },
        required: ["path"],
      }) { |args, _ctx| call(dispatcher, "open", args) }

    server.tool("ts_open_source", description: "Open a source string into a new editing session",
      input_schema: {
        type:       "object",
        properties: {
          source:   {type: "string"},
          language: {type: "string"},
        },
        required: ["source", "language"],
      }) { |args, _ctx| call(dispatcher, "open_source", args) }

    server.tool("ts_close", description: "Close an editing session",
      input_schema: SESSION_SCHEMA) { |args, _ctx| call(dispatcher, "close", args) }

    server.tool("ts_find", description: "Run a tree-sitter query and return matches with capture positions",
      input_schema: {
        type:       "object",
        properties: {
          session: {type: "string"},
          query:   {type: "string", description: "tree-sitter query source"},
          within:  {type: "string", description: "scope query restricting where the main query runs"},
        },
        required: ["session", "query"],
      }) { |args, _ctx| call(dispatcher, "find", args) }

    server.tool("ts_outline", description: "Structural outline of a session's source",
      input_schema: {
        type:       "object",
        properties: {session: {type: "string"}, depth: {type: "integer"}},
        required:   ["session"],
      }) { |args, _ctx| call(dispatcher, "outline", args) }

    server.tool("ts_node_at", description: "Smallest syntax node at a zero-based row/column",
      input_schema: {
        type:       "object",
        properties: {session: {type: "string"}, row: {type: "integer"}, column: {type: "integer"}},
        required:   ["session", "row", "column"],
      }) { |args, _ctx| call(dispatcher, "node_at", args) }

    server.tool("ts_source", description: "Current source of a session",
      input_schema: SESSION_SCHEMA) { |args, _ctx| call(dispatcher, "source", args) }

    server.tool("ts_diff", description: "Unified diff of a session's source against its original",
      input_schema: SESSION_SCHEMA) { |args, _ctx| call(dispatcher, "diff", args) }

    server.tool("ts_edit", description: "Apply an edit op to a session",
      input_schema: EDIT_SCHEMA) { |args, _ctx| call(dispatcher, "edit", args) }

    server.tool("ts_preview", description: "Test an edit op on a throwaway copy; the session stays untouched",
      input_schema: EDIT_SCHEMA) { |args, _ctx| call(dispatcher, "preview", args) }

    server.tool("ts_undo", description: "Undo the last edit",
      input_schema: SESSION_SCHEMA) { |args, _ctx| call(dispatcher, "undo", args) }

    server.tool("ts_redo", description: "Redo the last undone edit",
      input_schema: SESSION_SCHEMA) { |args, _ctx| call(dispatcher, "redo", args) }

    server.tool("ts_expect", description: "Assert a query's match count (count/min/max)",
      input_schema: {
        type:       "object",
        properties: {session: {type: "string"}, query: {type: "string"}, count: {type: "integer"}, min: {type: "integer"}, max: {type: "integer"}},
        required:   ["session", "query"],
      }) { |args, _ctx| call(dispatcher, "expect", args) }

    server.tool("ts_write", description: "Write a session's source back to disk",
      input_schema: {
        type:       "object",
        properties: {session: {type: "string"}, path: {type: "string"}},
        required:   ["session"],
      }) { |args, _ctx| call(dispatcher, "write", args) }

    server.tool("ts_recipes", description: "List named query recipes, optionally for one language",
      input_schema: {type: "object", properties: {language: {type: "string"}}}) { |args, _ctx| call(dispatcher, "recipes", args) }

    server.tool("ts_languages", description: "List supported languages",
      input_schema: {type: "object"}) { |args, _ctx| call(dispatcher, "languages", args) }
  end

  private def call(dispatcher : Dispatcher, command : String, args : Hash(String, JSON::Any)) : String | MCP::CallToolResult
    result = dispatcher.handle(command, JSON::Any.new(args))
    if result["error"]?.try(&.as_bool?)
      MCP::CallToolResult.error(result.to_json)
    else
      result.to_json
    end
  end
end
