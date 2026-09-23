# spec/session_spec.cr
require "./spec_helper"

describe TsEdit::Session do
  json  = %({"gamma": 3, "alpha": 1, "beta": 2})
  py    = "def greet(name):\n    return name\n\ndef shout(name):\n    return greet(name).upper()\n"
  c_src = "int main(void) {\n    return compute(first, second);\n}\n"

  it "replaces captured nodes" do
    query   = "([(function_definition name: (identifier) @n) (call function: (identifier) @n)] (#eq? @n \"greet\"))"
    session = TsEdit::Session.new(py, lang("python"))
    session.replace(query, "n", "welcome")
    session.source.should contain "def welcome(name):"
    session.source.should contain "welcome(name).upper()"
    session.edit_count.should eq 2
  end

  it "dynamically replaces nodes using a block" do
    query   = "(function_definition name: (identifier) @n)"
    session = TsEdit::Session.new(py, lang("python"))
    session.replace(query, "n") do |match|
      node = match["n"].not_nil!
      node.text(session.source).upcase
    end
    session.source.should contain "def GREET(name):"
    session.source.should contain "def SHOUT(name):"
  end

  it "dynamically inserts using a block" do
    session = TsEdit::Session.new(json, lang("json"))
    session.insert("(number) @n", "n", before: true, check: false) do |match|
      "/*#{match["n"].not_nil!.text(session.source)}*/ "
    end
    session.source.should contain "/*3*/ 3"
  end

  it "chains multiple operations (Fluent API) while persisting AST state" do
    session = TsEdit::Session.new(json, lang("json"))

    session
      .sort("(pair) @p", "p")
      .delete("(object (pair key: (string (string_content) @_k) (#eq? @_k \"alpha\")) @pair . \",\"? @comma)", ["pair", "comma"])

    # After sorting, "alpha": 1 is the first pair. Deleting the pair and the comma leaves the trailing space.
    session.source.should eq %({ "beta": 2, "gamma": 3})
    session.edit_count.should eq 4 # 3 sorts + 1 delete (pair+comma counts as 1 continuous range)
  end

  it "absorbs the whole line when deleting a line-level node" do
    source  = "{\n  \"name\": \"demo\",\n  \"debug\": false,\n  \"tags\": [\"a\"]\n}\n"
    query   = "(object (pair key: (string (string_content) @_k) (#eq? @_k \"debug\")) @pair . \",\"? @comma)"
    session = TsEdit::Session.new(source, lang("json"))
    session.delete(query, ["pair", "comma"])
    session.source.should eq "{\n  \"name\": \"demo\",\n  \"tags\": [\"a\"]\n}\n"
  end

  it "wraps captures with prefix and suffix" do
    session = TsEdit::Session.new(py, lang("python"))
    session.wrap("(function_definition name: (identifier) @n)", "n", prefix: "traced_", check: true)
    session.source.should contain "def traced_greet"
    session.source.should contain "def traced_shout"
  end

  it "swaps two captures within each match" do
    session = TsEdit::Session.new(c_src, lang("c"))
    session.swap("(argument_list (_) @a (_) @b)", "a", "b")
    session.source.should contain "compute(second, first)"
  end

  it "moves a capture relative to another, absorbing separators" do
    session = TsEdit::Session.new(c_src, lang("c"))
    session.move("(argument_list (_) @a (_) @b)", from: "a", to: "b", position: :after)
    session.source.should contain "compute(second, first)"
  end

  it "reorders nodes against a second query" do
    session = TsEdit::Session.new(py, lang("python"))
    session.reorder(
      "((function_definition name: (identifier) @_n) @fn (#eq? @_n \"shout\"))", "fn",
      to_query: "((function_definition name: (identifier) @_n) @t (#eq? @_n \"greet\"))", to_capture: "t",
      position: :before
    )
    session.source.should start_with "def shout"
  end

  it "sorts in reverse" do
    session = TsEdit::Session.new(json, lang("json"))
    session.sort("(pair) @p", "p", reverse: true)
    session.source.should eq %({"gamma": 3, "beta": 2, "alpha": 1})
  end

  it "dedupes identical siblings, keeping the first" do
    session = TsEdit::Session.new(%(["a", "b", "a"]), lang("json"))
    session.dedupe("(array (string) @s)", "s")
    session.source.should eq %(["a", "b"])
  end

  it "unwraps an inner capture by removing its outer wrapper" do
    py_src  = "print(calculate(10))"
    query   = "((call function: (identifier) @_f arguments: (argument_list (call) @inner)) @outer (#eq? @_f \"print\"))"
    session = TsEdit::Session.new(py_src, lang("python"))
    session.unwrap(query, "outer", "inner")
    session.source.should eq "calculate(10)"
  end

  it "overwrites a target with a source capture" do
    src     = "x = y + 1\n"
    query   = "(assignment left: (identifier) @target right: (binary_operator left: (identifier) @source right: (integer)))"
    session = TsEdit::Session.new(src, lang("python"))
    session.overwrite(query, "target", "source")
    session.source.should eq "y = y + 1\n"
  end

  it "duplicates a capture" do
    src     = "def greet(name):\n    return name\n"
    query   = "(function_definition name: (identifier) @n (#eq? @n \"greet\")) @func"
    session = TsEdit::Session.new(src, lang("python"))
    session.duplicate(query, "func")
    session.source.scan(/def greet/).size.should eq 2
  end

  it "extracts a capture and returns its original text" do
    src     = "def greet():\n    pass\n"
    query   = "(function_definition name: (identifier) @n (#eq? @n \"greet\")) @func"
    session = TsEdit::Session.new(src, lang("python"))
    session.extract(query, "func", "pass")
    session.source.should contain "pass"
    session.source.should_not contain "def greet():"
    session.extracted.first.should eq "def greet():\n    pass"
  end

  it "raises NoMatchesError when no capture matches" do
    session = TsEdit::Session.new(json, lang("json"))
    expect_raises(TsEdit::NoMatchesError, /no matches/) do
      session.replace("(number) @n", "missing", "x")
    end
  end

  it "raises SyntaxGuardError when the result would not parse" do
    session = TsEdit::Session.new(py, lang("python"))
    expect_raises(TsEdit::SyntaxGuardError) do
      session.delete("(function_definition name: (identifier) @n)", "n")
    end
  end

  it "skips the guard when check is overridden to false" do
    session = TsEdit::Session.new(py, lang("python"))
    session.delete("(function_definition name: (identifier) @n)", "n", check: false)
    session.source.should_not contain "def greet"
  end
end
