# src/ts-edit/languages.cr
require "./errors"
require "./tree_sitter"

module TsEdit::Languages
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

  COMMENT_TOKENS = {
    "crystal" => {"#", ""},
    "python"  => {"#", ""},
    "bash"    => {"#", ""},
    "c"       => {"//", ""},
  }

  @@custom            = Hash(String, Proc(TreeSitter::Language)).new
  @@custom_extensions = Hash(String, String).new
  @@custom_comments   = Hash(String, Tuple(String, String)).new

  def register(name : String, extensions : Array(String) = [] of String, comment_prefix : String? = nil, comment_suffix : String? = nil, &block : -> TreeSitter::Language) : Nil
    @@custom[name] = block
    @@custom_comments[name] = {comment_prefix, comment_suffix || ""} if comment_prefix
    extensions.each do |ext|
      @@custom_extensions[ext.starts_with?('.') ? ext : ".#{ext}"] = name
    end
  end

  def names : Array(String)
    (["bash", "c", "crystal", "json", "python"] + @@custom.keys).sort.uniq
  end

  def comment_tokens(name : String) : Tuple(String, String)
    @@custom_comments[name]? || COMMENT_TOKENS[name]? ||
      raise TreeSitter::Error.new("no comment tokens known for '#{name}'; pass explicit prefix:/suffix:")
  end

  def fetch(name : String) : TreeSitter::Language
    if factory = @@custom[name]?
      return factory.call
    end
    case name
    when "json"
      TreeSitter::Language.new(LibTreeSitter.tree_sitter_json, name)
    when "crystal"
      TreeSitter::Language.new(LibTreeSitter.tree_sitter_crystal, name)
    when "python"
      TreeSitter::Language.new(LibTreeSitter.tree_sitter_python, name)
    when "c"
      TreeSitter::Language.new(LibTreeSitter.tree_sitter_c, name)
    when "bash"
      TreeSitter::Language.new(LibTreeSitter.tree_sitter_bash, name)
    else
      raise TreeSitter::Error.new("unknown language '#{name}' (available: #{names.join(", ")})")
    end
  end

  def for_path(path : String) : TreeSitter::Language
    ext  = File.extname(path)
    name = @@custom_extensions[ext]? || EXTENSIONS[ext]? || raise(TreeSitter::Error.new("cannot infer a language from '#{ext}'; pass an explicit language"))
    fetch(name)
  end
end
