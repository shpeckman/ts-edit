# examples/library_usage.cr
require "../src/ts-edit"

# 1. Standard replacements using the fluent interface
json    = File.read("#{__DIR__}/samples/config.json")
session = TsEdit::Session.new(json, TsEdit::Languages.for_path("config.json"))

session
  .sort("(pair) @pair", "pair")
  .delete("(object (pair key: (string (string_content) @_k) (#eq? @_k \"debug\")) @pair . \",\"? @comma)", ["pair", "comma"])

puts "--- JSON after chained sort and delete ---"
puts session.source
puts "Total edits: #{session.edit_count}"

# 2. Block-based dynamic replacements
py         = File.read("#{__DIR__}/samples/script.py")
py_session = TsEdit::Session.new(py, TsEdit::Languages.for_path("script.py"))

query = "(function_definition name: (identifier) @n)"
py_session.replace(query, "n") do |match|
  name_node = match["n"].not_nil!
  # Use the matched text to generate the replacement string
  "traced_#{name_node.text(py_session.source).upcase}"
end

puts "\n--- Python after dynamic block replacement ---"
puts py_session.source

# 3. Syntax Guard protection
begin
  py_session.delete("(function_definition name: (identifier) @n)", "n")
rescue ex : TsEdit::SyntaxGuardError
  puts "\n--- Syntax Guard Intervention ---"
  puts "Guard stopped a breaking edit: #{ex.message}"
end
