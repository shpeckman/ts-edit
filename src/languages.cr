# src/languages.cr
require "./tree_sitter"

module Languages
  extend self

  EXTENSIONS = {
    ".cr"   => "crystal",
    ".json" => "json",
  }

  def names : Array(String)
    ["crystal", "json"]
  end

  def fetch(name : String) : TreeSitter::Language
    case name
    when "json"
      TreeSitter::Language.new(LibTreeSitter.tree_sitter_json)
    when "crystal"
      TreeSitter::Language.new(LibTreeSitter.tree_sitter_crystal)
    else
      raise TreeSitter::Error.new("unknown language '#{name}' (available: #{names.join(", ")})")
    end
  end

  def for_path(path : String) : TreeSitter::Language
    ext = File.extname(path)
    name = EXTENSIONS[ext]? || raise(TreeSitter::Error.new("cannot infer a language from '#{ext}'; pass --language"))
    fetch(name)
  end
end
