# spec/ops_spec.cr
require "./spec_helper"

describe TsEdit::Ops do
  json  = %({"gamma": 3, "alpha": 1, "beta": 2})
  py    = "def greet(name):\n    return name\n\ndef shout(name):\n    return greet(name).upper()\n"
  c_src = "int main(void) {\n    return compute(first, second);\n}\n"

  it "replaces captured nodes" do
    query  = "([(function_definition name: (identifier) @n) (call function: (identifier) @n)] (#eq? @n \"greet\"))"
    result = TsEdit::Ops.replace(py, lang("python"), query, "n", "welcome")
    result.source.should contain "def welcome(name):"
    result.source.should contain "welcome(name).upper()"
    result.edits.should eq 2
  end

  it "deletes captured nodes" do
    query  = "(object (pair key: (string (string_content) @_k) (#eq? @_k \"alpha\")) @pair . \",\"? @comma)"
    result = TsEdit::Ops.delete(json, lang("json"), query, ["pair", "comma"])
    result.source.should eq %({"gamma": 3,  "beta": 2})
  end

  it "absorbs the whole line when deleting a line-level node" do
    source = "{\n  \"name\": \"demo\",\n  \"debug\": false,\n  \"tags\": [\"a\"]\n}\n"
    query  = "(object (pair key: (string (string_content) @_k) (#eq? @_k \"debug\")) @pair . \",\"? @comma)"
    result = TsEdit::Ops.delete(source, lang("json"), query, ["pair", "comma"])
    result.source.should eq "{\n  \"name\": \"demo\",\n  \"tags\": [\"a\"]\n}\n"
  end

  it "inserts before and after captures" do
    before = TsEdit::Ops.insert(json, lang("json"), "(number) @n", "n", "/*", before: true, check: false)
    before.source.should contain "/*3"
    after = TsEdit::Ops.insert(json, lang("json"), "(number) @n", "n", "!", check: false)
    after.source.should contain "3!"
  end

  it "wraps captures with prefix and suffix" do
    result = TsEdit::Ops.wrap(py, lang("python"), "(function_definition name: (identifier) @n)", "n", prefix: "traced_", check: true)
    result.source.should contain "def traced_greet"
    result.source.should contain "def traced_shout"
  end

  it "swaps two captures within each match" do
    result = TsEdit::Ops.swap(c_src, lang("c"), "(argument_list (_) @a (_) @b)", "a", "b")
    result.source.should contain "compute(second, first)"
  end

  it "moves a capture relative to another, absorbing separators" do
    result = TsEdit::Ops.move(c_src, lang("c"), "(argument_list (_) @a (_) @b)", from: "a", to: "b", position: :after)
    result.source.should contain "compute(second, first)"
  end

  it "reorders nodes against a second query" do
    result = TsEdit::Ops.reorder(py, lang("python"),
      "((function_definition name: (identifier) @_n) @fn (#eq? @_n \"shout\"))", "fn",
      to_query: "((function_definition name: (identifier) @_n) @t (#eq? @_n \"greet\"))", to_capture: "t",
      position: :before)
    result.source.should start_with "def shout"
  end

  it "rejects an ambiguous reorder destination" do
    expect_raises(TsEdit::Error, /exactly one/) do
      TsEdit::Ops.reorder(py, lang("python"),
        "((function_definition name: (identifier) @_n) @fn (#eq? @_n \"shout\"))", "fn",
        to_query: "(function_definition name: (identifier) @t)", to_capture: "t")
    end
  end

  it "sorts sibling captures by text" do
    result = TsEdit::Ops.sort(json, lang("json"), "(pair) @p", "p")
    result.source.should eq %({"alpha": 1, "beta": 2, "gamma": 3})
  end

  it "sorts in reverse" do
    result = TsEdit::Ops.sort(json, lang("json"), "(pair) @p", "p", reverse: true)
    result.source.should eq %({"gamma": 3, "beta": 2, "alpha": 1})
  end

  it "dedupes identical siblings, keeping the first" do
    result = TsEdit::Ops.dedupe(%(["a", "b", "a"]), lang("json"), "(array (string) @s)", "s")
    result.source.should eq %(["a", "b"])
  end

  it "honors skip and limit" do
    result = TsEdit::Ops.replace(py, lang("python"), "(function_definition name: (identifier) @n)", "n", "x", skip: 1, limit: 1)
    result.source.should contain "def greet"
    result.source.should contain "def x"
    result.edits.should eq 1
  end

  it "raises NoMatchesError when no capture matches" do
    expect_raises(TsEdit::NoMatchesError, /no matches/) do
      TsEdit::Ops.replace(json, lang("json"), "(number) @n", "missing", "x")
    end
  end

  it "raises SyntaxGuardError when the result would not parse" do
    expect_raises(TsEdit::SyntaxGuardError) do
      TsEdit::Ops.delete(py, lang("python"), "(function_definition name: (identifier) @n)", "n")
    end
  end

  it "skips the guard with check: false" do
    result = TsEdit::Ops.delete(py, lang("python"), "(function_definition name: (identifier) @n)", "n", check: false)
    result.source.should_not contain "def greet"
    result.source.should_not contain "def shout"
  end

  it "reports zero edits when nothing changes" do
    result = TsEdit::Ops.sort(json, lang("json"), "(pair) @p", "p")
    again  = TsEdit::Ops.sort(result.source, lang("json"), "(pair) @p", "p")
    again.edits.should eq 0
    again.source.should eq result.source
  end

  it "rejects an invalid move position" do
    expect_raises(TsEdit::Error, /position/) do
      TsEdit::Ops.move(c_src, lang("c"), "(argument_list (_) @a (_) @b)", from: "a", to: "b", position: :sideways)
    end
  end
end
