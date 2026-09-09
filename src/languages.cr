# src/languages.cr
require "./tree_sitter"

module Languages
  extend self

  EXTENSIONS = {
    ".cr"   => "crystal",
    ".json" => "json",
    ".py"   => "python",
    ".c"    => "c",
    ".h"    => "c",
    ".sh"   => "bash",
    ".bash" => "bash",
  }

  def names : Array(String)
    ["bash", "c", "crystal", "json", "python"]
  end

  def fetch(name : String) : TreeSitter::Language
    case name
    when "json"
      TreeSitter::Language.new(LibTreeSitter.tree_sitter_json)
    when "crystal"
      TreeSitter::Language.new(LibTreeSitter.tree_sitter_crystal)
    when "python"
      TreeSitter::Language.new(LibTreeSitter.tree_sitter_python)
    when "c"
      TreeSitter::Language.new(LibTreeSitter.tree_sitter_c)
    when "bash"
      TreeSitter::Language.new(LibTreeSitter.tree_sitter_bash)
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
