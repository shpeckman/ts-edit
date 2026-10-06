# spec/scoped_spec.cr
require "./spec_helper"

describe "Session within:" do
  py = "def greet(name):\n    return name\n\ndef shout(name):\n    return name.upper()\n"

  it "narrows an op to a single function body" do
    session = TsEdit::Session.new(py, lang("python"))
    session.replace("((identifier) @i (#eq? @i \"name\"))", "i", "whom",
      within: %(((function_definition name: (identifier) @_f) @fn (#eq? @_f "greet"))))
    session.source.should contain "def greet(whom):"
    session.source.should contain "return whom\n"
    session.source.should contain "def shout(name):"
    session.source.should contain "return name.upper()"
  end

  it "raises NoMatchesError when the scope query matches nothing" do
    session = TsEdit::Session.new(py, lang("python"))
    expect_raises(TsEdit::NoMatchesError, /within/) do
      session.replace("(identifier) @i", "i", "x",
        within: %(((function_definition name: (identifier) @_f) @fn (#eq? @_f "missing"))))
    end
  end

  it "applies skip/limit to the merged scope matches" do
    session = TsEdit::Session.new(py, lang("python"))
    session.replace("((identifier) @i (#eq? @i \"name\"))", "i", "x", limit: 1,
      within: "(function_definition) @fn")
    session.source.should contain "def greet(x):"
    session.source.should contain "return name\n"
    session.source.should contain "def shout(name):"
  end

  it "scopes read-only find" do
    session = TsEdit::Session.new(py, lang("python"))
    all     = session.find("((identifier) @i (#eq? @i \"name\"))")
    scoped = session.find("((identifier) @i (#eq? @i \"name\"))",
      within: %(((function_definition name: (identifier) @_f) @fn (#eq? @_f "greet"))))
    all.size.should eq 4
    scoped.size.should eq 2
  end
end
