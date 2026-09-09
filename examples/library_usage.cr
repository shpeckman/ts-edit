# examples/library_usage.cr
require "../src/ts-edit"

json = File.read("#{__DIR__}/samples/config.json")
lang = TsEdit::Languages.for_path("config.json")

sorted = TsEdit::Ops.sort(json, lang, "(pair) @pair", "pair")
puts sorted.source

py = File.read("#{__DIR__}/samples/script.py")
renamed = TsEdit::Ops.replace(py, TsEdit::Languages.for_path("script.py"),
  File.read("#{__DIR__}/queries/python_rename_function.scm"), "name", "welcome")
puts renamed.source

begin
  TsEdit::Ops.delete(py, TsEdit::Languages.for_path("script.py"),
    "(function_definition name: (identifier) @n)", "n")
rescue ex : TsEdit::SyntaxGuardError
  puts "guard stopped a breaking edit: #{ex.message}"
end

parser = TsEdit::TreeSitter::Parser.new(TsEdit::Languages.fetch("crystal"))
tree   = parser.parse(File.read("#{__DIR__}/samples/app.cr"))
puts tree.root.sexp
