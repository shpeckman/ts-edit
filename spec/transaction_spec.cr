# spec/transaction_spec.cr
require "./spec_helper"

describe TsEdit::Session do
  json = %({"name": "demo", "debug": false})

  it "rolls back all edits when an op inside the block fails" do
    session = TsEdit::Session.new(json, lang("json"))
    expect_raises(TsEdit::SyntaxGuardError) do
      session.transaction do |s|
        s.sort("(pair) @p", "p")
        s.delete("(pair key: (string) @k)", "k")
      end
    end
    session.source.should eq json
    session.history_size.should eq 0
  end

  it "keeps edits when the block succeeds" do
    session = TsEdit::Session.new(json, lang("json"))
    session.transaction do |s|
      s.sort("(pair) @p", "p")
    end
    session.source.should eq %({"debug": false, "name": "demo"})
    session.history_size.should eq 1
  end

  it "re-raises non-guard errors after rollback" do
    session = TsEdit::Session.new(json, lang("json"))
    expect_raises(TsEdit::NoMatchesError) do
      session.transaction do |s|
        s.sort("(pair) @p", "p")
        s.replace("(number) @n", "n", "0")
      end
    end
    session.source.should eq json
    session.history_size.should eq 0
  end
end
