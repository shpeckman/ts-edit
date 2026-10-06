# spec/recipes_spec.cr
require "./spec_helper"

describe TsEdit::Recipes do
  it "fetches a named recipe" do
    TsEdit::Recipes.fetch("python", "rename_function").should contain "function_definition"
  end

  it "lists recipe names per language and overall" do
    TsEdit::Recipes.names("python").should eq ["list_functions", "rename_function"]
    TsEdit::Recipes.names.should contain "python/rename_function"
    TsEdit::Recipes.names("nope").should be_empty
  end

  it "raises for unknown languages and recipes" do
    expect_raises(TsEdit::TreeSitter::Error, /no recipes/) { TsEdit::Recipes.fetch("nope", "nope") }
    expect_raises(TsEdit::TreeSitter::Error, /unknown recipe/) { TsEdit::Recipes.fetch("python", "nope") }
  end

  it "round-trips a recipe through a session" do
    py      = "def greet(name):\n    return name\n\ndef shout(name):\n    return greet(name).upper()\n"
    session = TsEdit::Session.new(py, lang("python"))
    session.replace(TsEdit::Recipes.fetch("python", "rename_function"), "name", "salute")
    session.source.should contain "def salute(name):"
    session.source.should contain "salute(name).upper()"
  end

  it "compiles every embedded recipe against its language" do
    TsEdit::Recipes::RECIPES.each do |language, recipes|
      recipes.each_value do |query|
        TsEdit::TreeSitter::Query.new(lang(language), query)
      end
    end
  end
end
