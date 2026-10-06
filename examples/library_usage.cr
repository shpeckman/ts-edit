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

# 4. Dry-run preview, transactions, and file loading
file_session = TsEdit::Session.from_file("#{__DIR__}/samples/config.json")

preview = file_session.preview do |s|
  s.sort("(pair) @p", "p")
end
puts "\n--- Preview diff (file_session left untouched) ---"
puts preview.diff

begin
  file_session.transaction do |s|
    # Deleting a key but not its value is invalid JSON: the guard aborts the whole transaction.
    s.delete("(pair key: (string) @k)", "k")
  end
rescue ex : TsEdit::SyntaxGuardError
  puts "--- Transaction rolled back ---"
  puts "#{ex.message}; source unchanged: #{file_session.source == json}"
end

file_session.sort("(pair) @p", "p")
file_session.undo
puts "--- Undo restored pre-sort state: #{file_session.source == json} ---"
