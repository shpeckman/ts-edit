# spec/predicates_spec.cr
require "./spec_helper"

describe TsEdit::TreeSitter::Query do
  it "filters matches with a registered custom predicate" do
    TsEdit::TreeSitter::Query.register_predicate("longer-than?") do |args, captures, source|
      id    = args[0].as(UInt32)
      limit = args[1].as(String).to_i
      captures.select { |c| c.id == id }.all? { |c| c.node.text(source).size > limit }
    end

    json    = %({"gamma": 3, "alpha": 1, "beta": 2})
    query   = %((string (string_content) @key (#longer-than? @key 4)))
    session = TsEdit::Session.new(json, lang("json"))
    session.replace(query, "key", "k")
    session.source.should eq %({"k": 3, "k": 1, "beta": 2})
  end

  it "lets unknown predicates pass through" do
    json    = %({"a": 1})
    query   = %((string (string_content) @key) (#made-up? @key))
    session = TsEdit::Session.new(json, lang("json"))
    session.replace(query, "key", "k")
    session.source.should eq %({"k": 1})
  end
end
