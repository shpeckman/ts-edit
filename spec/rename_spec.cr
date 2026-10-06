# spec/rename_spec.cr
require "./spec_helper"

describe "Session#rename" do
  py     = "def greet(name):\n    return name\n\ndef shout(name):\n    return greet(name).upper()\n"
  nested = "def outer():\n    value = 1\n    def inner():\n        value = 2\n        return value\n    return value\n"

  it "renames a definition and its references within an explicit scope" do
    session = TsEdit::Session.new(py, lang("python"))
    session.rename("((function_definition name: (identifier) @def) (#eq? @def \"greet\"))", "def", "welcome", scope: ["module"])
    session.source.should contain "def welcome(name):"
    session.source.should contain "welcome(name).upper()"
    session.source.should_not contain "greet"
    session.edit_count.should eq 2
    session.last_edits.size.should eq 2
  end

  it "scopes to the nearest enclosing scope by default" do
    session = TsEdit::Session.new(py, lang("python"))
    session.rename("((function_definition name: (identifier) @def) (#eq? @def \"greet\"))", "def", "welcome")
    session.source.should contain "def welcome(name):"
    session.source.should contain "greet(name).upper()"
  end

  it "leaves same-named identifiers in enclosing scopes untouched" do
    session = TsEdit::Session.new(nested, lang("python"))
    session.rename("((function_definition name: (identifier) @_f (block (assignment left: (identifier) @var))) (#eq? @_f \"inner\") (#eq? @var \"value\"))", "var", "other")
    session.source.should eq "def outer():\n    value = 1\n    def inner():\n        other = 2\n        return other\n    return value\n"
  end

  it "honours an explicit scope list" do
    session = TsEdit::Session.new(nested, lang("python"))
    session.rename("((function_definition name: (identifier) @_f (block (assignment left: (identifier) @var))) (#eq? @_f \"inner\") (#eq? @var \"value\"))", "var", "other", scope: ["module"])
    session.source.should eq "def outer():\n    other = 1\n    def inner():\n        other = 2\n        return other\n    return other\n"
  end

  it "supports undo like any other op" do
    session = TsEdit::Session.new(py, lang("python"))
    session.rename("((function_definition name: (identifier) @def) (#eq? @def \"greet\"))", "def", "welcome")
    session.undo
    session.source.should eq py
  end
end
