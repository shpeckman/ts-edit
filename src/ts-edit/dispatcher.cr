# src/ts-edit/dispatcher.cr
require "json"
require "./session"
require "./recipes"
require "./languages"
require "./diff"

class TsEdit::Dispatcher
  @sessions : Hash(String, Session) = {} of String => Session
  @originals : Hash(String, String) = {} of String => String
  @next_id : Int32 = 0

  def handle(command : String, params : JSON::Any = JSON::Any.new({} of String => JSON::Any)) : JSON::Any
    case command
    when "open"        then cmd_open(params)
    when "open_source" then cmd_open_source(params)
    when "close"       then cmd_close(params)
    when "find"        then cmd_find(params)
    when "outline"     then cmd_outline(params)
    when "node_at"     then cmd_node_at(params)
    when "source"      then cmd_source(params)
    when "diff"        then cmd_diff(params)
    when "edit"        then cmd_edit(params)
    when "preview"     then cmd_preview(params)
    when "undo"        then cmd_undo(params)
    when "redo"        then cmd_redo(params)
    when "expect"      then cmd_expect(params)
    when "write"       then cmd_write(params)
    when "recipes"     then cmd_recipes(params)
    when "languages"   then cmd_languages
    else                    raise Error.new("unknown command '#{command}'")
    end
  rescue ex : SyntaxGuardError
    error_json(ex) do |j|
      j.field "line", ex.line
      j.field "column", ex.column
      j.field "excerpt", ex.excerpt
    end
  rescue ex : Error
    error_json(ex)
  rescue ex : KeyError | TypeCastError
    error_json(Error.new("invalid params: #{ex.message}"))
  end

  private def cmd_open(params : JSON::Any) : JSON::Any
    language = opt_str(params, "language").try { |name| Languages.fetch(name) }
    check = opt_bool(params, "check") || true
    register Session.from_file(str(params, "path"), language: language, check: check)
  end

  private def cmd_open_source(params : JSON::Any) : JSON::Any
    register Session.new(str(params, "source"), Languages.fetch(str(params, "language")))
  end

  private def cmd_close(params : JSON::Any) : JSON::Any
    id, _session = session_for(params)
    @sessions.delete(id)
    @originals.delete(id)
    build_json { |j| j.object { j.field "closed", true } }
  end

  private def cmd_find(params : JSON::Any) : JSON::Any
    _id, session = session_for(params)
    matches = session.find(str(params, "query"), within: opt_str(params, "within"))
    build_json do |j|
      j.object do
        j.field "matches" do
          j.array { matches.each { |match| match_json(j, match, session.source) } }
        end
      end
    end
  end

  private def cmd_outline(params : JSON::Any) : JSON::Any
    _id, session = session_for(params)
    entries = session.outline(depth: opt_int(params, "depth") || 2)
    build_json do |j|
      j.object do
        j.field "outline" do
          j.array { entries.each { |entry| outline_json(j, entry) } }
        end
      end
    end
  end

  private def cmd_node_at(params : JSON::Any) : JSON::Any
    _id, session = session_for(params)
    node = session.node_at(params["row"].as_i, params["column"].as_i)
    build_json do |j|
      j.object do
        if node
          j.field "node" { node_json(j, node, session.source) }
        else
          j.field "node", nil
        end
      end
    end
  end

  private def cmd_source(params : JSON::Any) : JSON::Any
    _id, session = session_for(params)
    build_json { |j| j.object { j.field "source", session.source } }
  end

  private def cmd_diff(params : JSON::Any) : JSON::Any
    id, session = session_for(params)
    build_json { |j| j.object { j.field "diff", Diff.unified(@originals[id], session.source) } }
  end

  private def cmd_edit(params : JSON::Any) : JSON::Any
    _id, session = session_for(params)
    before = session.source
    apply_op(session, params)
    build_json do |j|
      j.object do
        j.field "edit_count", session.edit_count
        j.field "source_changed", session.source != before
        j.field "last_edits" do
          j.array { session.last_edits.each { |edit| edit_json(j, edit) } }
        end
      end
    end
  end

  private def cmd_preview(params : JSON::Any) : JSON::Any
    _id, session = session_for(params)
    clone = Session.new(session.source, session.language, check: session.check)
    apply_op(clone, params)
    build_json do |j|
      j.object do
        j.field "source", clone.source
        j.field "diff", Diff.unified(session.source, clone.source)
        j.field "edit_count", clone.edit_count
      end
    end
  end

  private def cmd_undo(params : JSON::Any) : JSON::Any
    _id, session = session_for(params)
    session.undo
    history_json(session)
  end

  private def cmd_redo(params : JSON::Any) : JSON::Any
    _id, session = session_for(params)
    session.redo
    history_json(session)
  end

  private def cmd_expect(params : JSON::Any) : JSON::Any
    _id, session = session_for(params)
    session.expect(str(params, "query"), count: opt_int(params, "count"), min: opt_int(params, "min"), max: opt_int(params, "max"))
    build_json { |j| j.object { j.field "ok", true } }
  end

  private def cmd_write(params : JSON::Any) : JSON::Any
    _id, session = session_for(params)
    path = opt_str(params, "path")
    path ? session.write(path) : session.write
    build_json { |j| j.object { j.field "written", path || session.path } }
  end

  private def cmd_recipes(params : JSON::Any) : JSON::Any
    names = Recipes.names(opt_str(params, "language"))
    build_json { |j| j.object { j.field "recipes", names } }
  end

  private def cmd_languages : JSON::Any
    build_json { |j| j.object { j.field "languages", Languages.names } }
  end

  private def apply_op(session : Session, params : JSON::Any) : Nil
    query = str(params, "query")
    case str(params, "op")
    when "replace"   then session.replace(query, capture_param(params), str(params, "replacement"), **common(params))
    when "delete"    then session.delete(query, capture_param(params), **common(params))
    when "insert"    then session.insert(query, capture_param(params), str(params, "text"), **common(params), before: opt_bool(params, "before") || false)
    when "wrap"      then session.wrap(query, capture_param(params), **common(params), prefix: opt_str(params, "prefix"), suffix: opt_str(params, "suffix"))
    when "swap"      then session.swap(query, str(params, "first"), str(params, "second"), **common(params))
    when "move"      then session.move(query, str(params, "from"), str(params, "to"), **common(params), position: position_param(params))
    when "reorder"   then session.reorder(query, capture_param(params), str(params, "to_query"), str(params, "to_capture"), **common(params), position: position_param(params))
    when "sort"      then session.sort(query, capture_param(params), **common(params), reverse: opt_bool(params, "reverse") || false)
    when "dedupe"    then session.dedupe(query, capture_param(params), **common(params))
    when "unwrap"    then session.unwrap(query, str(params, "outer"), str(params, "inner"), **common(params))
    when "overwrite" then session.overwrite(query, str(params, "target"), str(params, "source_capture"), **common(params))
    when "duplicate" then session.duplicate(query, capture_param(params), **common(params), position: position_param(params))
    when "extract"   then session.extract(query, capture_param(params), str(params, "replacement"), **common(params))
    when "comment"   then session.comment(query, capture_param(params), **common(params), prefix: opt_str(params, "prefix"), suffix: opt_str(params, "suffix"))
    when "uncomment" then session.uncomment(query, capture_param(params), **common(params), prefix: opt_str(params, "prefix"), suffix: opt_str(params, "suffix"))
    when "indent"    then session.indent(query, capture_param(params), **common(params), by: opt_int(params, "by") || 2)
    when "outdent"   then session.outdent(query, capture_param(params), **common(params), by: opt_int(params, "by") || 2)
    when "toggle"    then session.toggle(query, capture_param(params), str(params, "a"), str(params, "b"), **common(params))
    when "rename"    then session.rename(query, str(params, "capture"), str(params, "to"), **common(params), scope: str_array(params, "scope"))
    else                  raise Error.new("unknown op '#{params["op"]?}'")
    end
  end

  private def register(session : Session) : JSON::Any
    @next_id += 1
    id = "s#{@next_id}"
    @sessions[id] = session
    @originals[id] = session.source
    build_json do |j|
      j.object do
        j.field "session", id
        j.field "language", session.language.name
        j.field "outline" do
          j.array { session.outline.each { |entry| outline_json(j, entry) } }
        end
      end
    end
  end

  private def session_for(params : JSON::Any) : Tuple(String, Session)
    id = str(params, "session")
    session = @sessions[id]? || raise Error.new("unknown session '#{id}'")
    {id, session}
  end

  private def common(params : JSON::Any)
    {skip: opt_int(params, "skip") || 0, limit: opt_int(params, "limit"), within: opt_str(params, "within"), check: opt_bool(params, "check")}
  end

  private def capture_param(params : JSON::Any) : String | Array(String)
    raw = params["capture"]? || params["captures"]? || raise Error.new("missing 'capture' param")
    raw.as_s? || raw.as_a.map(&.as_s)
  end

  private def position_param(params : JSON::Any) : Symbol
    case opt_str(params, "position")
    when nil, "after" then :after
    when "before"     then :before
    else                   raise Error.new("invalid position (expected \"before\" or \"after\")")
    end
  end

  private def str(params : JSON::Any, key : String) : String
    params[key].as_s
  end

  private def opt_str(params : JSON::Any, key : String) : String?
    params[key]?.try(&.as_s)
  end

  private def opt_int(params : JSON::Any, key : String) : Int32?
    params[key]?.try(&.as_i)
  end

  private def opt_bool(params : JSON::Any, key : String) : Bool?
    params[key]?.try(&.as_bool)
  end

  private def str_array(params : JSON::Any, key : String) : Array(String)?
    params[key]?.try { |value| value.as_a.map(&.as_s) }
  end

  private def history_json(session : Session) : JSON::Any
    build_json do |j|
      j.object do
        j.field "edit_count", session.edit_count
        j.field "can_undo", session.can_undo?
        j.field "can_redo", session.can_redo?
      end
    end
  end

  private def match_json(j : JSON::Builder, match : TreeSitter::Match, source : String) : Nil
    j.object do
      j.field "pattern_index", match.pattern_index
      j.field "captures" do
        j.array { match.captures.each { |cap| capture_json(j, cap, source) } }
      end
    end
  end

  private def capture_json(j : JSON::Builder, cap : TreeSitter::Capture, source : String) : Nil
    j.object do
      j.field "name", cap.name
      node_json_fields(j, cap.node, source)
    end
  end

  private def node_json(j : JSON::Builder, node : TreeSitter::Node, source : String) : Nil
    j.object do
      j.field "type", node.type
      node_json_fields(j, node, source)
    end
  end

  private def node_json_fields(j : JSON::Builder, node : TreeSitter::Node, source : String) : Nil
    start_point = node.start_point
    end_point = node.end_point
    j.field "text", node.text(source)
    j.field "start_byte", node.start_byte
    j.field "end_byte", node.end_byte
    j.field "start_row", start_point.row
    j.field "start_column", start_point.column
    j.field "end_row", end_point.row
    j.field "end_column", end_point.column
  end

  private def outline_json(j : JSON::Builder, entry : Session::OutlineEntry) : Nil
    j.object do
      j.field "type", entry.type
      j.field "name", entry.name
      j.field "row", entry.row
      j.field "column", entry.column
    end
  end

  private def edit_json(j : JSON::Builder, edit : Edit) : Nil
    j.object do
      j.field "start_byte", edit.start_byte
      j.field "end_byte", edit.end_byte
      j.field "replacement", edit.replacement
    end
  end

  private def error_json(ex : Exception) : JSON::Any
    build_json do |j|
      j.object do
        j.field "error", true
        j.field "type", ex.class.name
        j.field "message", ex.message
      end
    end
  end

  private def error_json(ex : Exception, & : JSON::Builder ->) : JSON::Any
    build_json do |j|
      j.object do
        j.field "error", true
        j.field "type", ex.class.name
        j.field "message", ex.message
        yield j
      end
    end
  end

  private def build_json(& : JSON::Builder ->) : JSON::Any
    JSON.parse(JSON.build { |j| yield j })
  end
end
