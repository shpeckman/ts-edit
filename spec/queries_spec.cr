# spec/queries_spec.cr
require "./spec_helper"

describe TsEdit::Queries do
  it "loads a query file and runs it through a session" do
    py      = "def greet(name):\n    return name\n\ndef shout(name):\n    return greet(name).upper()\n"
    query   = TsEdit::Queries.load("#{__DIR__}/../examples/queries/python_rename_function.scm")
    session = TsEdit::Session.new(py, lang("python"))
    session.replace(query, "name", "welcome")
    session.source.should contain "def welcome(name):"
    session.source.should contain "welcome(name).upper()"
  end

  it "raises for a missing query file" do
    expect_raises(TsEdit::Error, /not found/) { TsEdit::Queries.load("no/such/query.scm") }
  end
end
