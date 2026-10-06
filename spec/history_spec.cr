# spec/history_spec.cr
require "./spec_helper"

describe TsEdit::Session do
  json = %({"gamma": 3, "alpha": 1, "beta": 2})

  it "undoes and redoes edits" do
    session = TsEdit::Session.new(json, lang("json"))
    session.sort("(pair) @p", "p")
    session.source.should_not eq json
    session.can_undo?.should be_true
    session.undo
    session.source.should eq json
    session.can_redo?.should be_true
    session.redo
    session.source.should eq %({"alpha": 1, "beta": 2, "gamma": 3})
  end

  it "tracks history size across chained ops" do
    session = TsEdit::Session.new(json, lang("json"))
    session.history_size.should eq 0
    session.replace("(number) @n", "n", "0")
    session.sort("(pair) @p", "p")
    session.history_size.should eq 2
    session.undo.undo
    session.history_size.should eq 0
    session.source.should eq json
  end

  it "clears the redo stack on a new edit" do
    session = TsEdit::Session.new(json, lang("json"))
    session.replace("(number) @n", "n", "0")
    session.undo
    session.replace("(number) @n", "n", "1")
    session.can_redo?.should be_false
    session.source.should eq %({"gamma": 1, "alpha": 1, "beta": 1})
  end

  it "raises when undoing or redoing with empty history" do
    session = TsEdit::Session.new(json, lang("json"))
    expect_raises(TsEdit::Error, "nothing to undo") { session.undo }
    expect_raises(TsEdit::Error, "nothing to redo") { session.redo }
  end

  it "restores edit_count and extracted on undo and redo" do
    session = TsEdit::Session.new(json, lang("json"))
    session.extract("(number) @n", "n", "null")
    session.extracted.size.should eq 3
    count = session.edit_count
    session.undo
    session.edit_count.should eq 0
    session.extracted.should be_empty
    session.redo
    session.edit_count.should eq count
    session.extracted.size.should eq 3
  end
end
