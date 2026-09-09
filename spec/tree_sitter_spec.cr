# spec/tree_sitter_spec.cr
require "./spec_helper"

describe TsEdit::TreeSitter do
  json = %({"name": "demo", "tags": ["a", "b"]})

  it "parses JSON and exposes the root node" do
    tree = TsEdit::TreeSitter::Parser.new(lang("json")).parse(json)
    tree.root.type.should eq "document"
    tree.has_error?.should be_false
  end

  it "detects syntax errors" do
    tree = TsEdit::TreeSitter::Parser.new(lang("json")).parse(%({"a": }))
    tree.has_error?.should be_true
  end

  it "navigates nodes with types, byte ranges and text" do
    tree   = TsEdit::TreeSitter::Parser.new(lang("json")).parse(json)
    object = tree.root.named_child(0).not_nil!
    object.type.should eq "object"
    pair = object.named_child(0).not_nil!
    pair.type.should eq "pair"
    pair.parent.not_nil!.type.should eq "object"
    pair.text(json).should eq %("name": "demo")
    json.byte_slice(pair.start_byte, pair.end_byte - pair.start_byte).should eq pair.text(json)
  end

  it "renders the tree as an s-expression" do
    tree = TsEdit::TreeSitter::Parser.new(lang("json")).parse(json)
    tree.root.sexp.should contain "(pair"
  end

  it "runs queries and reports captures with ranges" do
    tree  = TsEdit::TreeSitter::Parser.new(lang("json")).parse(json)
    query = TsEdit::TreeSitter::Query.new(lang("json"), "(pair value: (string) @v)")
    nodes = query.matches(tree.root, json).flat_map(&.captures).map(&.node)
    nodes.size.should eq 1
    nodes[0].text(json).should eq %("demo")
  end

  it "filters matches with the eq? predicate" do
    source = "def greet\nend\n\ndef shout\n  greet()\nend\n"
    tree   = TsEdit::TreeSitter::Parser.new(lang("crystal")).parse(source)
    query = TsEdit::TreeSitter::Query.new(lang("crystal"),
      "([(method_def name: (identifier) @n) (call method: (identifier) @n)] (#eq? @n \"greet\"))")
    names = query.matches(tree.root, source).flat_map(&.captures).map { |c| c.node.text(source) }
    names.should eq ["greet", "greet"]
  end

  it "filters matches with the match? predicate" do
    tree = TsEdit::TreeSitter::Parser.new(lang("json")).parse(json)
    query = TsEdit::TreeSitter::Query.new(lang("json"),
      "((pair key: (string (string_content) @k)) (#match? @k \"^na\"))")
    keys = query.matches(tree.root, json).flat_map(&.captures).map { |c| c.node.text(json) }
    keys.should eq ["name"]
  end

  it "filters matches with the any-of? predicate" do
    tree = TsEdit::TreeSitter::Parser.new(lang("json")).parse(json)
    query = TsEdit::TreeSitter::Query.new(lang("json"),
      "((pair key: (string (string_content) @k)) (#any-of? @k \"tags\" \"other\"))")
    keys = query.matches(tree.root, json).flat_map(&.captures).map { |c| c.node.text(json) }
    keys.should eq ["tags"]
  end

  it "supports the custom has-parent? predicate" do
    source = "x = [1, 2]\n"
    tree   = TsEdit::TreeSitter::Parser.new(lang("python")).parse(source)
    query = TsEdit::TreeSitter::Query.new(lang("python"),
      "((identifier) @i (#has-parent? @i \"assignment\"))")
    names = query.matches(tree.root, source).flat_map(&.captures).map { |c| c.node.text(source) }
    names.should eq ["x"]
  end

  it "supports the custom has-ancestor? predicate" do
    source = "def f\n  [1, 2].each do |x|\n    x\n  end\nend\n"
    tree   = TsEdit::TreeSitter::Parser.new(lang("crystal")).parse(source)
    query = TsEdit::TreeSitter::Query.new(lang("crystal"),
      "((identifier) @i (#has-ancestor? @i \"block\"))")
    names = query.matches(tree.root, source).flat_map(&.captures).map { |c| c.node.text(source) }
    names.should contain "x"
    names.should_not contain "f"
  end

  it "supports the custom nth-child? predicate" do
    tree = TsEdit::TreeSitter::Parser.new(lang("json")).parse(json)
    query = TsEdit::TreeSitter::Query.new(lang("json"),
      "((pair) @p (#nth-child? @p \"1\"))")
    pairs = query.matches(tree.root, json).flat_map(&.captures).map { |c| c.node.text(json) }
    pairs.should eq [%("tags": ["a", "b"])]
  end

  it "raises QueryError for an invalid query" do
    expect_raises(TsEdit::TreeSitter::QueryError) do
      TsEdit::TreeSitter::Query.new(lang("json"), "(no_such_node @x)")
    end
  end

  it "reparses incrementally from an edited tree" do
    parser = TsEdit::TreeSitter::Parser.new(lang("json"))
    tree   = parser.parse(json)
    edits  = [TsEdit::Edit.new(9, 15, "42")]
    result = TsEdit::Editor.apply(json, edits)
    tree.edit(TsEdit::Editor.input_edit(json, result, edits))
    reparsed = parser.parse(result, tree)
    reparsed.has_error?.should be_false
    reparsed.root.text(result).should eq result
  end
end
