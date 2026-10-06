# src/ts-edit/recipes.cr
require "./errors"
require "./tree_sitter"

module TsEdit::Recipes
  extend self

  RECIPES = {
    "bash" => {
      "rename_function" => "([(function_definition name: (word) @name) (command_name (word) @name)] (#eq? @name \"build\"))",
      "list_functions"  => "(function_definition name: (word) @name)",
    },
    "c" => {
      "rename_function" => "([(function_definition declarator: (function_declarator declarator: (identifier) @name)) (call_expression function: (identifier) @name)] (#eq? @name \"add\"))",
      "list_functions"  => "(function_definition declarator: (function_declarator declarator: (identifier) @name))",
    },
    "crystal" => {
      "rename_method" => "([(method_def name: (identifier) @name) (call method: (identifier) @name)] (#eq? @name \"greet\"))",
      "list_methods"  => "(method_def name: (identifier) @name)",
    },
    "json" => {
      "find_pair" => "(object (pair key: (string (string_content) @_key)) @pair . \",\"? @comma (#eq? @_key \"debug\"))",
      "list_keys" => "(pair key: (string (string_content) @key))",
    },
    "python" => {
      "rename_function" => "([(function_definition name: (identifier) @name) (call function: (identifier) @name)] (#eq? @name \"greet\"))",
      "list_functions"  => "(function_definition name: (identifier) @name)",
    },
  }

  def fetch(language : String, name : String) : String
    recipes = RECIPES[language]? ||
              raise TreeSitter::Error.new("no recipes for language '#{language}' (available: #{RECIPES.keys.join(", ")})")
    recipes[name]? ||
      raise TreeSitter::Error.new("unknown recipe '#{name}' for #{language} (available: #{recipes.keys.join(", ")})")
  end

  def names(language : String? = nil) : Array(String)
    if language
      RECIPES[language]?.try(&.keys.sort) || [] of String
    else
      RECIPES.flat_map { |lang, recipes| recipes.keys.map { |n| "#{lang}/#{n}" } }.sort
    end
  end
end
