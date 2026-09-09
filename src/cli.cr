# src/cli.cr
require "option_parser"
require "./ts-edit"

module TsEdit
  USAGE = <<-USAGE
  Usage: ts-edit <command> [options] FILE...

  Commands:
    sexp      print the syntax tree of each FILE
    query     run a tree-sitter query and print matches
    replace   replace the text of captured nodes
    delete    delete captured nodes
    insert    insert text before or after captured nodes
    wrap      wrap captured nodes with prefix and/or suffix text
    swap      swap the text of two captures within each match
    move      move a capture before or after another capture within each match
    reorder   move captured nodes before or after a node matched by a second query
    sort      sort captured sibling nodes by their text
    dedupe    delete duplicate captured sibling nodes, keeping the first
    apply     run a script of edit operations (one command per line) atomically

  Selection:
    -q, --query QUERY       tree-sitter query string
    -F, --query-file PATH   read the query from a file
    -c, --capture NAME      capture to act on (repeatable)
        --skip N            skip the first N matches
        --limit N           act on at most N matches

  Command-specific:
    swap      -c FIRST -c SECOND
    move      --from CAP --to CAP [--position before|after]
    reorder   -c CAP --to-query QUERY --to-capture CAP [--position before|after]
    wrap      --prefix TEXT and/or --suffix TEXT
    insert    --before TEXT or --after TEXT
    replace   --with TEXT
    sort      [--reverse]
    apply     -s, --script PATH

  Other options:
    -l, --language NAME     language (bash, c, crystal, json, python); inferred from the FILE extension otherwise
    -w, --write             write changes back to each FILE (default: print the result to stdout)
        --no-check          do not reparse the result to reject edits that introduce syntax errors
    -h, --help              show help
    -v, --version           show version

  Extra query predicates: #has-parent?, #has-ancestor?, #nth-child? (and their not- variants)
  USAGE

  EDIT_COMMANDS = {:replace, :delete, :insert, :wrap, :swap, :move, :reorder, :sort, :dedupe}

  class Options
    property language      : String?       = nil
    property query         : String?       = nil
    property query_file    : String?       = nil
    property capture       : Array(String) = [] of String
    property with_text     : String?       = nil
    property insert_text   : String?       = nil
    property insert_before : Bool          = false
    property prefix        : String?       = nil
    property suffix        : String?       = nil
    property from          : String?       = nil
    property to            : String?       = nil
    property to_query      : String?       = nil
    property to_capture    : String?       = nil
    property position      : String        = "after"
    property reverse       : Bool          = false
    property skip          : Int32         = 0
    property limit         : Int32?        = nil
    property script        : String?       = nil
    property write         : Bool          = false
    property check         : Bool          = true
    property files         : Array(String) = [] of String
  end

  def self.run(argv : Array(String)) : Int32
    command = argv.shift?
    case command
    when "sexp"    then cmd_sexp(argv)
    when "query"   then cmd_query(argv)
    when "replace" then cmd_edit(argv, :replace)
    when "delete"  then cmd_edit(argv, :delete)
    when "insert"  then cmd_edit(argv, :insert)
    when "wrap"    then cmd_edit(argv, :wrap)
    when "swap"    then cmd_edit(argv, :swap)
    when "move"    then cmd_edit(argv, :move)
    when "reorder" then cmd_edit(argv, :reorder)
    when "sort"    then cmd_edit(argv, :sort)
    when "dedupe"  then cmd_edit(argv, :dedupe)
    when "apply"   then cmd_apply(argv)
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
      parser.on("-l LANG", "--language LANG", "language (bash, c, crystal, json, python)") { |v| opts.language = v }
      parser.on("-q QUERY", "--query QUERY", "tree-sitter query string") { |v| opts.query = v }
      parser.on("-F PATH", "--query-file PATH", "read the query from a file") { |v| opts.query_file = v }
      parser.on("-c NAME", "--capture NAME", "capture to act on (repeatable)") { |v| opts.capture << v }
      parser.on("--with TEXT", "replacement text (replace)") { |v| opts.with_text = v }
      parser.on("--before TEXT", "insert before the capture (insert)") { |v| opts.insert_text = v; opts.insert_before = true }
      parser.on("--after TEXT", "insert after the capture (insert)") { |v| opts.insert_text = v; opts.insert_before = false }
      parser.on("--prefix TEXT", "text inserted at the start of the capture (wrap)") { |v| opts.prefix = v }
      parser.on("--suffix TEXT", "text inserted at the end of the capture (wrap)") { |v| opts.suffix = v }
      parser.on("--from CAP", "capture to move (move)") { |v| opts.from = v }
      parser.on("--to CAP", "capture to move next to (move)") { |v| opts.to = v }
      parser.on("--to-query QUERY", "query locating the destination (reorder)") { |v| opts.to_query = v }
      parser.on("--to-capture CAP", "capture marking the destination (reorder)") { |v| opts.to_capture = v }
      parser.on("--position POS", "before or after (move, reorder; default after)") { |v| opts.position = v }
      parser.on("--reverse", "sort descending (sort)") { opts.reverse = true }
      parser.on("--skip N", "skip the first N matches") { |v| opts.skip = v.to_i }
      parser.on("--limit N", "act on at most N matches") { |v| opts.limit = v.to_i }
      parser.on("-s PATH", "--script PATH", "edit script (apply)") { |v| opts.script = v }
      parser.on("-w", "--write", "write changes back to each FILE") { opts.write = true }
      parser.on("--no-check", "skip the syntax-error recheck") { opts.check = false }
      parser.on("-h", "--help", "show help") { puts parser; exit 0 }
      parser.invalid_option { |flag| raise "unknown option: #{flag}" }
    end
  end

  private def self.finish_parse(parser : OptionParser, opts : Options, argv : Array(String)) : Nil
    parser.parse(argv)
    opts.files = argv.dup
    raise "missing FILE argument" if opts.files.empty?
  end

  private def self.load_source(file : String, opts : Options) : Tuple(String, TreeSitter::Language)
    source   = File.read(file)
    language = opts.language ? Languages.fetch(opts.language.not_nil!) : Languages.for_path(file)
    parser   = TreeSitter::Parser.new(language)
    STDERR.puts "warning: #{file} contains syntax errors" if parser.parse(source).has_error?
    {source, language}
  end

  private def self.query_source(opts : Options) : String
    query      = opts.query
    query_file = opts.query_file
    if query && query_file
      raise "pass either --query or --query-file, not both"
    elsif query
      query
    elsif query_file
      File.read(query_file)
    else
      raise "missing --query or --query-file"
    end
  end

  private def self.run_op(command : Symbol, opts : Options, source : String, language : TreeSitter::Language) : Ops::Result
    query = query_source(opts)
    case command
    when :replace
      raise "missing --capture NAME" if opts.capture.empty?
      raise "missing --with TEXT" if opts.with_text.nil?
      Ops.replace(source, language, query, opts.capture, opts.with_text.not_nil!, skip: opts.skip, limit: opts.limit, check: opts.check)
    when :delete
      raise "missing --capture NAME" if opts.capture.empty?
      Ops.delete(source, language, query, opts.capture, skip: opts.skip, limit: opts.limit, check: opts.check)
    when :insert
      raise "missing --capture NAME" if opts.capture.empty?
      raise "missing --before TEXT or --after TEXT" if opts.insert_text.nil?
      Ops.insert(source, language, query, opts.capture, opts.insert_text.not_nil!, before: opts.insert_before, skip: opts.skip, limit: opts.limit, check: opts.check)
    when :wrap
      raise "missing --capture NAME" if opts.capture.empty?
      Ops.wrap(source, language, query, opts.capture, prefix: opts.prefix, suffix: opts.suffix, skip: opts.skip, limit: opts.limit, check: opts.check)
    when :swap
      raise "swap needs exactly two --capture names" unless opts.capture.size == 2
      Ops.swap(source, language, query, opts.capture[0], opts.capture[1], skip: opts.skip, limit: opts.limit, check: opts.check)
    when :move
      raise "missing --from CAPTURE" unless opts.from
      raise "missing --to CAPTURE" unless opts.to
      Ops.move(source, language, query, opts.from.not_nil!, opts.to.not_nil!, position: parse_position(opts), skip: opts.skip, limit: opts.limit, check: opts.check)
    when :reorder
      raise "missing --capture NAME" if opts.capture.empty?
      raise "missing --to-query QUERY" unless opts.to_query
      raise "missing --to-capture CAPTURE" unless opts.to_capture
      Ops.reorder(source, language, query, opts.capture, opts.to_query.not_nil!, opts.to_capture.not_nil!, position: parse_position(opts), skip: opts.skip, limit: opts.limit, check: opts.check)
    when :sort
      raise "missing --capture NAME" if opts.capture.empty?
      Ops.sort(source, language, query, opts.capture, reverse: opts.reverse, skip: opts.skip, limit: opts.limit, check: opts.check)
    when :dedupe
      raise "missing --capture NAME" if opts.capture.empty?
      Ops.dedupe(source, language, query, opts.capture, skip: opts.skip, limit: opts.limit, check: opts.check)
    else
      raise "unknown edit command: #{command}"
    end
  end

  private def self.parse_position(opts : Options) : Symbol
    case opts.position
    when "before" then :before
    when "after"  then :after
    else               raise "invalid --position '#{opts.position}' (expected before or after)"
    end
  end

  private def self.output(file : String, original : String, result : String, edit_count : Int32, opts : Options) : Nil
    if opts.write
      File.write(file, result) unless result == original
      STDERR.puts(result == original ? "#{file}: unchanged" : "#{file}: updated (#{edit_count} edit(s))")
    else
      if opts.files.size > 1
        puts "==> #{file} <=="
        print result
        puts unless result.ends_with?('\n')
      else
        print result
      end
    end
  end

  private def self.cmd_sexp(argv : Array(String)) : Int32
    opts = Options.new
    finish_parse(base_parser(opts, "Usage: ts-edit sexp [options] FILE..."), opts, argv)
    opts.files.each do |file|
      source, language = load_source(file, opts)
      puts "==> #{file} <==" if opts.files.size > 1
      puts TreeSitter::Parser.new(language).parse(source).root.sexp
    end
    0
  rescue ex
    STDERR.puts "error: #{ex.message}"
    1
  end

  private def self.cmd_query(argv : Array(String)) : Int32
    opts = Options.new
    finish_parse(base_parser(opts, "Usage: ts-edit query [options] FILE..."), opts, argv)
    failed = false
    opts.files.each do |file|
      begin
        source, language = load_source(file, opts)
        query   = TreeSitter::Query.new(language, query_source(opts))
        tree    = TreeSitter::Parser.new(language).parse(source)
        matches = query.matches(tree.root, source)
        matches = matches[opts.skip..] if opts.skip > 0
        if limit = opts.limit
          matches = matches.first(limit)
        end
        filter = opts.capture
        count  = 0
        puts "==> #{file} <==" if opts.files.size > 1
        matches.each do |match|
          match.captures.each do |capture|
            next unless filter.empty? || filter.includes?(capture.name)
            node    = capture.node
            preview = node.text(source).gsub('\n', "\\n")
            preview = preview[0, 57] + "..." if preview.size > 60
            puts "@#{capture.name} #{node.type} [#{node.start_byte}...#{node.end_byte}] #{preview.inspect}"
            count += 1
          end
        end
        STDERR.puts "#{file}: no captures" if count == 0
      rescue ex
        STDERR.puts "#{file}: error: #{ex.message}"
        failed = true
      end
    end
    failed ? 1 : 0
  end

  private def self.cmd_edit(argv : Array(String), command : Symbol) : Int32
    opts = Options.new
    finish_parse(base_parser(opts, "Usage: ts-edit #{command} [options] FILE..."), opts, argv)
    failed = false
    opts.files.each do |file|
      failed = true unless edit_file(file, opts, command)
    end
    failed ? 1 : 0
  end

  private def self.edit_file(file : String, opts : Options, command : Symbol) : Bool
    source, language = load_source(file, opts)
    result = run_op(command, opts, source, language)
    output(file, source, result.source, result.edits, opts)
    true
  rescue ex : SyntaxGuardError
    STDERR.puts "#{file}: error: refusing to apply: #{ex.message} (use --no-check to force)"
    false
  rescue ex
    STDERR.puts "#{file}: error: #{ex.message}"
    false
  end

  private def self.cmd_apply(argv : Array(String)) : Int32
    opts = Options.new
    finish_parse(base_parser(opts, "Usage: ts-edit apply --script PATH [options] FILE..."), opts, argv)
    script = opts.script || raise "missing --script PATH"
    steps  = parse_script(script)
    raise "script #{script} contains no operations" if steps.empty?
    failed = false
    opts.files.each do |file|
      failed = true unless apply_script_to_file(file, opts, steps)
    end
    failed ? 1 : 0
  end

  private def self.parse_script(path : String) : Array(Tuple(Symbol, Options))
    steps = [] of Tuple(Symbol, Options)
    File.each_line(path) do |line|
      stripped = line.strip
      next if stripped.empty? || stripped.starts_with?('#')
      tokens   = tokenize(stripped)
      cmd_name = tokens.shift? || next
      command  = EDIT_COMMANDS.find { |c| c.to_s == cmd_name }
      unless command
        raise "#{path}: unknown command '#{cmd_name}' (expected one of: #{EDIT_COMMANDS.join(", ")})"
      end
      opts = Options.new
      base_parser(opts, "").parse(tokens)
      raise "#{path}: unexpected argument(s) on line '#{stripped}': #{tokens.join(" ")}" unless tokens.empty?
      steps << {command, opts}
    end
    steps
  end

  private def self.tokenize(line : String) : Array(String)
    tokens   = [] of String
    current  = String::Builder.new
    building = false
    quote : Char? = nil
    escaped = false
    line.each_char do |ch|
      if escaped
        current << ch
        escaped = false
      elsif ch == '\\' && quote != '\''
        escaped  = true
        building = true
      elsif q = quote
        if ch == q
          quote = nil
        else
          current << ch
        end
      elsif ch == '\'' || ch == '"'
        quote    = ch
        building = true
      elsif ch.whitespace?
        if building
          tokens << current.to_s
          current  = String::Builder.new
          building = false
        end
      else
        current << ch
        building = true
      end
    end
    raise "unterminated quote in script line: #{line}" if quote
    tokens << current.to_s if building
    tokens
  end

  private def self.apply_script_to_file(file : String, outer : Options, steps : Array(Tuple(Symbol, Options))) : Bool
    source   = File.read(file)
    language = outer.language ? Languages.fetch(outer.language.not_nil!) : Languages.for_path(file)
    parser   = TreeSitter::Parser.new(language)
    STDERR.puts "warning: #{file} contains syntax errors" if parser.parse(source).has_error?
    current    = source
    edit_count = 0
    steps.each_with_index do |(command, opts), i|
      opts.check &&= outer.check
      begin
        result = run_op(command, opts, current, language)
      rescue ex : SyntaxGuardError
        raise SyntaxGuardError.new("step #{i + 1} (#{command}) #{ex.message}")
      end
      edit_count += result.edits
      current = result.source
    end
    output(file, source, current, edit_count, outer)
    true
  rescue ex : SyntaxGuardError
    STDERR.puts "#{file}: error: refusing to apply: #{ex.message} (use --no-check to force)"
    false
  rescue ex
    STDERR.puts "#{file}: error: #{ex.message}"
    false
  end
end

exit TsEdit.run(ARGV)
