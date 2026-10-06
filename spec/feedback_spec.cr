# spec/feedback_spec.cr
require "./spec_helper"

describe TsEdit::Session do
  py   = "def greet(name):\n    return name\n\ndef shout(name):\n    return greet(name).upper()\n"
  json = %({"alpha": 1})

  describe "SyntaxGuardError diagnostics" do
    it "reports line, column, and excerpt for a breaking edit" do
      session = TsEdit::Session.new(py, lang("python"))
      ex = expect_raises(TsEdit::SyntaxGuardError) do
        session.delete("(function_definition name: (identifier) @n)", "n")
      end
      ex.line.should eq 1
      ex.column.should_not be_nil
      ex.excerpt.to_s.should contain "def"
      ex.message.to_s.should contain "the edit would introduce syntax errors"
      ex.message.to_s.should contain "line 1, column"
    end

    it "reports diagnostics for invalid initial source" do
      ex = expect_raises(TsEdit::SyntaxGuardError) do
        TsEdit::Session.new("def broken(:", lang("python"))
      end
      ex.line.should eq 1
      ex.excerpt.should eq "def broken(:"
      ex.message.to_s.should contain "initial source has syntax errors"
    end
  end

  describe "#last_edits" do
    it "is empty before any op" do
      TsEdit::Session.new(json, lang("json")).last_edits.should be_empty
    end

    it "records the edits applied by the last op" do
      session = TsEdit::Session.new(json, lang("json"))
      session.replace("(number) @n", "n", "2")
      session.last_edits.size.should eq 1
      session.last_edits[0].replacement.should eq "2"
    end

    it "is empty when an op matches but changes nothing" do
      session = TsEdit::Session.new(py, lang("python"))
      session.wrap("(function_definition name: (identifier) @n)", "n", prefix: "traced_")
      session.last_edits.should_not be_empty
      TsEdit::Session.new(json, lang("json")).tap { |s| s.sort("(pair) @p", "p") }.last_edits.should be_empty
    end
  end

  describe "#expect" do
    it "passes and returns self when the count matches" do
      session = TsEdit::Session.new(py, lang("python"))
      session.expect("(function_definition) @f", count: 2).should be session
    end

    it "raises when the count differs" do
      session = TsEdit::Session.new(py, lang("python"))
      ex      = expect_raises(TsEdit::Error) { session.expect("(function_definition) @f", count: 3) }
      ex.message.to_s.should contain "expected 3 match(es), found 2"
    end

    it "supports min and max constraints" do
      session = TsEdit::Session.new(py, lang("python"))
      session.expect("(function_definition) @f", min: 1, max: 3)
      expect_raises(TsEdit::Error) { session.expect("(function_definition) @f", min: 3) }
      expect_raises(TsEdit::Error) { session.expect("(function_definition) @f", max: 1) }
    end

    it "requires at least one constraint" do
      session = TsEdit::Session.new(py, lang("python"))
      expect_raises(ArgumentError) { session.expect("(function_definition) @f") }
    end
  end
end
