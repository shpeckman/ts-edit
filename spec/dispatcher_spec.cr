# spec/dispatcher_spec.cr
require "./spec_helper"

private def jparams(raw : String) : JSON::Any
  JSON.parse(raw)
end

private def open_py(dispatcher : TsEdit::Dispatcher) : String
  result = dispatcher.handle("open_source", jparams(<<-JSON))
    {"source": "def greet(name):\\n    return name\\n\\ndef shout(name):\\n    return greet(name).upper()\\n", "language": "python"}
    JSON
  result["session"].as_s
end

describe TsEdit::Dispatcher do
  it "opens a source session with language and outline" do
    dispatcher = TsEdit::Dispatcher.new
    result = dispatcher.handle("open_source", jparams(%({"source": "def f():\\n    pass\\n", "language": "python"})))
    result["session"].as_s.should eq "s1"
    result["language"].as_s.should eq "python"
    result["outline"].as_a.first["type"].as_s.should eq "function_definition"
  end

  it "finds matches with capture positions" do
    dispatcher = TsEdit::Dispatcher.new
    sid = open_py(dispatcher)
    result = dispatcher.handle("find", jparams(%({"session": "#{sid}", "query": "(function_definition name: (identifier) @n)"})))
    matches = result["matches"].as_a
    matches.size.should eq 2
    cap = matches[0]["captures"][0]
    cap["name"].as_s.should eq "n"
    cap["text"].as_s.should eq "greet"
    cap["start_row"].as_i.should eq 0
    cap["start_column"].as_i.should eq 4
  end

  it "applies edits and reports them" do
    dispatcher = TsEdit::Dispatcher.new
    sid = open_py(dispatcher)
    result = dispatcher.handle("edit", jparams(<<-JSON))
      {"session": "#{sid}", "op": "replace", "query": "((function_definition name: (identifier) @n) (#eq? @n \\"greet\\"))", "capture": "n", "replacement": "welcome"}
      JSON
    result["edit_count"].as_i.should eq 1
    result["source_changed"].as_bool.should be_true
    result["last_edits"].as_a.first["replacement"].as_s.should eq "welcome"
    source = dispatcher.handle("source", jparams(%({"session": "#{sid}"})))
    source["source"].as_s.should contain "def welcome(name):"
  end

  it "previews without mutating the session" do
    dispatcher = TsEdit::Dispatcher.new
    sid = open_py(dispatcher)
    result = dispatcher.handle("preview", jparams(<<-JSON))
      {"session": "#{sid}", "op": "replace", "query": "(identifier) @i", "capture": "i", "replacement": "x", "limit": 1}
      JSON
    result["source"].as_s.should contain "def x(name):"
    result["diff"].as_s.should contain "-def greet"
    result["diff"].as_s.should contain "+def x"
    source = dispatcher.handle("source", jparams(%({"session": "#{sid}"})))
    source["source"].as_s.should contain "def greet(name):"
  end

  it "undoes edits" do
    dispatcher = TsEdit::Dispatcher.new
    sid = open_py(dispatcher)
    dispatcher.handle("edit", jparams(<<-JSON))
      {"session": "#{sid}", "op": "replace", "query": "(function_definition name: (identifier) @n)", "capture": "n", "replacement": "f", "limit": 1}
      JSON
    result = dispatcher.handle("undo", jparams(%({"session": "#{sid}"})))
    result["can_redo"].as_bool.should be_true
    source = dispatcher.handle("source", jparams(%({"session": "#{sid}"})))
    source["source"].as_s.should contain "def greet(name):"
  end

  it "diffs against the original source" do
    dispatcher = TsEdit::Dispatcher.new
    sid = open_py(dispatcher)
    dispatcher.handle("edit", jparams(<<-JSON))
      {"session": "#{sid}", "op": "replace", "query": "(function_definition name: (identifier) @n)", "capture": "n", "replacement": "f", "limit": 1}
      JSON
    result = dispatcher.handle("diff", jparams(%({"session": "#{sid}"})))
    result["diff"].as_s.should contain "-def greet"
    result["diff"].as_s.should contain "+def f"
  end

  it "reports syntax guard violations with position details" do
    dispatcher = TsEdit::Dispatcher.new
    sid = open_py(dispatcher)
    result = dispatcher.handle("edit", jparams(<<-JSON))
      {"session": "#{sid}", "op": "delete", "query": "(function_definition name: (identifier) @n)", "capture": "n"}
      JSON
    result["error"].as_bool.should be_true
    result["type"].as_s.should eq "TsEdit::SyntaxGuardError"
    result["line"].as_i.should eq 1
    result["column"].as_i.should_not be_nil
    result["excerpt"].as_s.should contain "def"
  end

  it "reports unknown sessions and commands" do
    dispatcher = TsEdit::Dispatcher.new
    result = dispatcher.handle("source", jparams(%({"session": "nope"})))
    result["error"].as_bool.should be_true
    result["message"].as_s.should contain "unknown session"
    result = dispatcher.handle("bogus", jparams(%({})))
    result["error"].as_bool.should be_true
    result["message"].as_s.should contain "unknown command"
  end

  it "checks postconditions" do
    dispatcher = TsEdit::Dispatcher.new
    sid = open_py(dispatcher)
    dispatcher.handle("expect", jparams(%({"session": "#{sid}", "query": "(function_definition) @f", "count": 2})))["ok"].as_bool.should be_true
    result = dispatcher.handle("expect", jparams(%({"session": "#{sid}", "query": "(function_definition) @f", "count": 5})))
    result["error"].as_bool.should be_true
  end
end
