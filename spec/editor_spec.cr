# spec/editor_spec.cr
require "./spec_helper"

describe TsEdit::Editor do
  it "applies a single replacement" do
    TsEdit::Editor.apply("hello world", [TsEdit::Edit.new(6, 11, "there")]).should eq "hello there"
  end

  it "applies multiple edits in one pass" do
    edits = [TsEdit::Edit.new(0, 1, "b"), TsEdit::Edit.new(4, 5, "e")]
    TsEdit::Editor.apply("a-c-d", edits).should eq "b-c-e"
  end

  it "applies insertions at a point" do
    TsEdit::Editor.apply("ac", [TsEdit::Edit.new(1, 1, "b")]).should eq "abc"
  end

  it "dedupes identical edits" do
    edits = [TsEdit::Edit.new(0, 1, "x"), TsEdit::Edit.new(0, 1, "x")]
    TsEdit::Editor.apply("ab", edits).should eq "xb"
  end

  it "raises ConflictError on overlapping edits" do
    edits = [TsEdit::Edit.new(0, 3, "x"), TsEdit::Edit.new(2, 5, "y")]
    expect_raises(TsEdit::ConflictError) do
      TsEdit::Editor.apply("abcdef", edits)
    end
  end

  it "computes a covering InputEdit" do
    source = "a\nb\nc\n"
    edits  = [TsEdit::Edit.new(2, 3, "bb"), TsEdit::Edit.new(4, 5, "cc")]
    result = TsEdit::Editor.apply(source, edits)
    ie     = TsEdit::Editor.input_edit(source, result, edits)
    ie.start_byte.should eq 2_u32
    ie.old_end_byte.should eq 5_u32
    ie.new_end_byte.should eq 7_u32
    ie.start_point.row.should eq 1_u32
    ie.start_point.column.should eq 0_u32
    ie.new_end_point.row.should eq 2_u32
    ie.new_end_point.column.should eq 2_u32
  end
end
