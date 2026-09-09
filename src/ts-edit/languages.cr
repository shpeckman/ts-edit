# src/ts-edit/languages.cr
require "./errors"
require "./tree_sitter"

module TsEdit
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

    @@custom            = Hash(String, Proc(TreeSitter::Language)).new
    @@custom_extensions = Hash(String, String).new

    def register(name : String, extensions : Array(String) = [] of String, &block : -> TreeSitter::Language) : Nil
      @@custom[name] = block
      extensions.each do |ext|
        @@custom_extensions[ext.starts_with?('.') ? ext : ".#{ext}"] = name
      end
    end

    def names : Array(String)
      (["bash", "c", "crystal", "json", "python"] + @@custom.keys).sort.uniq
    end

    def fetch(name : String) : TreeSitter::Language
      if factory = @@custom[name]?
        return factory.call
      end
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
      ext  = File.extname(path)
      name = @@custom_extensions[ext]? || EXTENSIONS[ext]? || raise(TreeSitter::Error.new("cannot infer a language from '#{ext}'; pass an explicit language"))
      fetch(name)
    end
  end
end
