# spec/languages_spec.cr
require "./spec_helper"

describe TsEdit::Languages do
  it "fetches built-in languages by name" do
    TsEdit::Languages.fetch("crystal").should be_a TsEdit::TreeSitter::Language
    TsEdit::Languages.names.should contain "python"
  end

  it "infers languages from file extensions" do
    TsEdit::Languages.for_path("x.py").should be_a TsEdit::TreeSitter::Language
    TsEdit::Languages.for_path("x.sh").should be_a TsEdit::TreeSitter::Language
    TsEdit::Languages.for_path("x.h").should be_a TsEdit::TreeSitter::Language
  end

  it "raises for unknown languages and extensions" do
    expect_raises(TsEdit::Error, /unknown language/) { TsEdit::Languages.fetch("cobol") }
    expect_raises(TsEdit::Error, /cannot infer/) { TsEdit::Languages.for_path("x.xyz") }
  end

  it "registers custom languages with extension mapping" do
    TsEdit::Languages.register("json5", [".json5"]) { TsEdit::Languages.fetch("json") }
    TsEdit::Languages.for_path("x.json5").should be_a TsEdit::TreeSitter::Language
    TsEdit::Languages.names.should contain "json5"
  end
end
