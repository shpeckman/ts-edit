# src/ts-edit.cr
require "option_parser"
require "./tree_sitter"
require "./languages"
require "./editor"

module TsEdit
  VERSION = "0.1.0"

  USAGE = <<-USAGE
  Usage: ts-edit <command> [options] FILE

  Commands:
    sexp      print the syntax tree of FILE
    query     run a tree-sitter query and print matches
    replace   replace the text of captured nodes
    delete    delete captured nodes
    insert    insert text before or after captured nodes

  Options:
    -l, --language NAME    language (crystal, json); inferred from the FILE extension otherwise
    -q, --query QUERY      tree-sitter query string
    -F, --query-file PATH  read the query from a file
    -c, --capture NAME     capture to print or edit
        --with TEXT        replacement text (replace)
        --before TEXT      text to insert before the capture (insert)
        --after TEXT       text to insert after the capture (insert)
    -w, --write            write changes back to FILE (default: print the result to stdout)
        --no-check         do not reparse the result to reject edits that introduce syntax errors
    -h, --help             show help
    -v, --version          show version
  USAGE

  class Options
    property language      : String?       = nil
    property query         : String?       = nil
    property query_file    : String?       = nil
    property capture       : Array(String) = [] of String
    property with_text     : String?       = nil
    property insert_text   : String?       = nil
    property insert_before : Bool          = false
    property write         : Bool          = false
    property check         : Bool          = true
    property file          : String?       = nil
  end

  def self.run(argv : Array(String)) : Int32
    command = argv.shift?
    case command
    when "sexp"    then cmd_sexp(argv)
    when "query"   then cmd_query(argv)
    when "replace" then cmd_edit(argv, :replace)
    when "delete"  then cmd_edit(argv, :delete)
    when "insert"  then cmd_edit(argv, :insert)
    when "-v", "--version"
      puts VERSION
      0
    when "-h", "--help", "help"
      puts USAGE
      0
    when nil
      STDERR.puts USAGE
      1
    else
      STDERR.puts "unknown command: #{command}"
      STDERR.puts USAGE
      1
    end
  rescue ex
    STDERR.puts "error: #{ex.message}"
    1
  end

  private def self.base_parser(opts : Options, banner : String) : OptionParser
    OptionParser.new do |parser|
      parser.banner = banner
      parser.on("-l LANG", "--language LANG", "language (crystal, json)") { |v| opts.language = v }
      parser.on("-q QUERY", "--query QUERY", "tree-sitter query string") { |v| opts.query = v }
      parser.on("-F PATH", "--query-file PATH", "read the query from a file") { |v| opts.query_file = v }
      parser.on("-c NAME", "--capture NAME", "capture to print or edit (repeatable)") { |v| opts.capture << v }
      parser.on("--with TEXT", "replacement text (replace)") { |v| opts.with_text = v }
      parser.on("--before TEXT", "insert before the capture (insert)") { |v| opts.insert_text = v; opts.insert_before = true }
      parser.on("--after TEXT", "insert after the capture (insert)") { |v| opts.insert_text = v; opts.insert_before = false }
      parser.on("-w", "--write", "write changes back to FILE") { opts.write = true }
      parser.on("--no-check", "skip the syntax-error recheck") { opts.check = false }
      parser.on("-h", "--help", "show help") { puts parser; exit 0 }
      parser.invalid_option { |flag| raise "unknown option: #{flag}" }
    end
  end

  private def self.finish_parse(parser : OptionParser, opts : Options, argv : Array(String)) : Nil
    parser.parse(argv)
    opts.file = argv[0]? || raise "missing FILE argument"
  end

  private def self.load(opts : Options) : Tuple(String, TreeSitter::Language, TreeSitter::Tree)
    file     = opts.file.not_nil!
    source   = File.read(file)
    language = opts.language ? Languages.fetch(opts.language.not_nil!) : Languages.for_path(file)
    tree     = TreeSitter::Parser.new(language).parse(source)
    STDERR.puts "warning: #{file} contains syntax errors" if tree.has_error?
    {source, language, tree}
  end

  private def self.build_query(language : TreeSitter::Language, opts : Options) : TreeSitter::Query
    query      = opts.query
    query_file = opts.query_file
    source = if query && query_file
               raise "pass either --query or --query-file, not both"
             elsif query
               query
             elsif query_file
               File.read(query_file)
             else
               raise "missing --query or --query-file"
             end
    TreeSitter::Query.new(language, source)
  end

  private def self.cmd_sexp(argv : Array(String)) : Int32
    opts = Options.new
    finish_parse(base_parser(opts, "Usage: ts-edit sexp [options] FILE"), opts, argv)
    _source, _language, tree = load(opts)
    puts tree.root.sexp
    0
  end

  private def self.cmd_query(argv : Array(String)) : Int32
    opts = Options.new
    finish_parse(base_parser(opts, "Usage: ts-edit query [options] FILE"), opts, argv)
    source, language, tree = load(opts)
    query  = build_query(language, opts)
    filter = opts.capture
    count  = 0
    query.matches(tree.root, source).each do |match|
      match.captures.each do |capture|
        next unless filter.empty? || filter.includes?(capture.name)
        node    = capture.node
        preview = node.text(source).gsub('\n', "\\n")
        preview = preview[0, 57] + "..." if preview.size > 60
        puts "@#{capture.name} #{node.type} [#{node.start_byte}...#{node.end_byte}] #{preview.inspect}"
        count += 1
      end
    end
    STDERR.puts "#{count} capture(s)" if count == 0
    0
  end

  private def self.cmd_edit(argv : Array(String), command : Symbol) : Int32
    opts = Options.new
    finish_parse(base_parser(opts, "Usage: ts-edit #{command} [options] FILE"), opts, argv)
    capture_names = opts.capture
    raise "missing --capture NAME" if capture_names.empty?
    case command
    when :replace
      raise "missing --with TEXT" if opts.with_text.nil?
    when :insert
      raise "missing --before TEXT or --after TEXT" if opts.insert_text.nil?
    end
    source, language, tree = load(opts)
    query = build_query(language, opts)
    edits = [] of Edit
    query.matches(tree.root, source).each do |match|
      match.captures.each do |capture|
        next unless capture_names.includes?(capture.name)
        node = capture.node
        case command
        when :replace
          edits << Edit.new(node.start_byte, node.end_byte, opts.with_text.not_nil!)
        when :delete
          edits << Edit.new(node.start_byte, node.end_byte, "")
        when :insert
          text = opts.insert_text.not_nil!
          if opts.insert_before
            edits << Edit.new(node.start_byte, node.start_byte, text)
          else
            edits << Edit.new(node.end_byte, node.end_byte, text)
          end
        end
      end
    end
    raise "no matches for capture(s) #{capture_names.map { |n| "@#{n}" }.join(", ")}" if edits.empty?
    result = Editor.apply(source, edits)
    if opts.check && TreeSitter::Parser.new(language).parse(result).has_error?
      raise "refusing to apply: the edit would introduce syntax errors (use --no-check to force)"
    end
    if opts.write
      File.write(opts.file.not_nil!, result)
      STDERR.puts "applied #{edits.uniq.size} edit(s) to #{opts.file}"
    else
      print result
    end
    0
  end
end

exit TsEdit.run(ARGV)
