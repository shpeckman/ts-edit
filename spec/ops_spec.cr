# spec/ops_spec.cr
require "./spec_helper"

describe TsEdit::Session do
  py = "def greet(name):\n    return name\n"

  it "comments and uncomments captures using language defaults" do
    session = TsEdit::Session.new(py, lang("python"))
    session.comment("(function_definition name: (identifier) @n)", "n", check: false)
    session.source.should contain "# greet"
    session.uncomment("(comment) @c", "c", check: false)
    session.source.should eq py
  end

  it "comments with C-style delimiters" do
    c_src   = "int main(void) {\n    return 0;\n}\n"
    session = TsEdit::Session.new(c_src, lang("c"))
    session.comment("(return_statement) @r", "r")
    session.source.should contain "// return 0;"
  end

  it "raises when the language has no known comment tokens" do
    session = TsEdit::Session.new(%({"a": 1}), lang("json"))
    expect_raises(TsEdit::Error, /comment tokens/) { session.comment("(pair) @p", "p") }
  end

  it "comments with explicit delimiters" do
    session = TsEdit::Session.new(%({"a": 1}), lang("json"))
    session.comment("(number) @n", "n", prefix: "/*", suffix: "*/", check: false)
    session.source.should eq %({"a": /* 1 */})
  end

  it "indents and outdents captured blocks" do
    session = TsEdit::Session.new(py, lang("python"))
    session.indent("(return_statement) @r", "r", by: 4, check: false)
    session.source.should contain "        return name"
    session.outdent("(return_statement) @r", "r", by: 4, check: false)
    session.source.should eq py
  end

  it "toggles capture text between two values" do
    session = TsEdit::Session.new(%({"debug": false}), lang("json"))
    session.toggle("(false) @v", "v", "false", "true")
    session.source.should eq %({"debug": true})
    session.toggle("(true) @v", "v", "false", "true")
    session.source.should eq %({"debug": false})
  end

  it "raises NoMatchesError when no capture matches either toggle value" do
    session = TsEdit::Session.new(%({"debug": null}), lang("json"))
    expect_raises(TsEdit::NoMatchesError) { session.toggle("(null) @v", "v", "false", "true") }
  end
end
