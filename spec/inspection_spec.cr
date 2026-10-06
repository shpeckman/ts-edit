# spec/inspection_spec.cr
require "./spec_helper"

describe TsEdit::Session do
  py = "def greet(name):\n    return name\n\ndef shout(name):\n    return greet(name).upper()\n"

  describe "#find" do
    it "returns read-only matches without mutating the session" do
      session = TsEdit::Session.new(py, lang("python"))
      matches = session.find("(function_definition name: (identifier) @n)")
      matches.size.should eq 2
      matches[0]["n"].not_nil!.text(session.source).should eq "greet"
      matches[1]["n"].not_nil!.text(session.source).should eq "shout"
      session.source.should eq py
      session.edit_count.should eq 0
      session.history_size.should eq 0
    end
  end

  describe "#node_at" do
    it "returns the smallest node spanning a zero-based row/column" do
      session = TsEdit::Session.new(py, lang("python"))
      node    = session.node_at(0, 4)
      node.should_not be_nil
      node.not_nil!.type.should eq "identifier"
      node.not_nil!.text(session.source).should eq "greet"
    end

    it "locates nodes on later lines" do
      session = TsEdit::Session.new(py, lang("python"))
      node    = session.node_at(3, 5)
      node.should_not be_nil
      node.not_nil!.type.should eq "identifier"
      node.not_nil!.text(session.source).should eq "shout"
    end
  end

  describe "#outline" do
    it "lists named top-level definitions with 1-based positions" do
      session = TsEdit::Session.new(py, lang("python"))
      entries = session.outline
      fns     = entries.select { |e| e.type == "function_definition" }
      fns.map(&.name).should eq ["greet", "shout"]
      fns[0].row.should eq 1
      fns[0].column.should eq 1
      fns[1].row.should eq 4
    end

    it "includes named children up to the requested depth" do
      json    = %({\n  "alpha": 1,\n  "beta": 2\n}\n)
      session = TsEdit::Session.new(json, lang("json"))
      pairs   = session.outline(depth: 2).select { |e| e.type == "pair" }
      pairs.size.should eq 2
      pairs[0].name.should eq %("alpha")
      pairs[0].row.should eq 2
      session.outline(depth: 1).none? { |e| e.type == "pair" }.should be_true
    end

    it "outlines the bundled python sample" do
      session = TsEdit::Session.from_file("#{__DIR__}/../examples/samples/script.py")
      session.outline.map(&.name).compact.should eq ["greet", "shout", "whisper"]
    end
  end
end
