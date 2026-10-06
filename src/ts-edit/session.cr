# src/ts-edit/session.cr
require "set"
require "./errors"
require "./tree_sitter"
require "./editor"

class TsEdit::Session
  getter source     : String
  getter language   : TreeSitter::Language
  getter tree       : TreeSitter::Tree
  getter edit_count : Int32         = 0
  getter extracted  : Array(String) = [] of String
  getter last_edits : Array(Edit)   = [] of Edit
  getter path       : String?       = nil
  property check    : Bool

  @undo_stack : Array(Snapshot) = [] of Snapshot
  @redo_stack : Array(Snapshot) = [] of Snapshot

  struct Preview
    getter source     : String
    getter diff       : String
    getter edit_count : Int32

    def initialize(@source : String, @diff : String, @edit_count : Int32)
    end
  end

  struct OutlineEntry
    getter type   : String
    getter name   : String?
    getter row    : Int32
    getter column : Int32

    def initialize(@type : String, @name : String?, @row : Int32, @column : Int32)
    end
  end

  def initialize(@source : String, @language : TreeSitter::Language, @check : Bool = true, @path : String? = nil)
    @parser = TreeSitter::Parser.new(@language)
    @tree   = @parser.parse(@source)
    raise syntax_guard_error("initial source has syntax errors", @tree, @source) if @check && @tree.has_error?
  end

  def self.from_file(path : String, language : TreeSitter::Language? = nil, check : Bool = true) : self
    new(File.read(path), language || Languages.for_path(path), check: check, path: path)
  end

  def self.process(path : String, check : Bool = true, & : Session ->) : self
    session  = from_file(path, check: check)
    original = session.source
    yield session
    session.write if session.source != original
    session
  end

  def write(path : String? = nil) : self
    target = path || @path || raise Error.new("no path associated with this session; pass one explicitly")
    File.write(target, @source)
    self
  end

  def transaction(& : Session ->) : self
    snap = snapshot
    undo = @undo_stack.dup
    redo = @redo_stack.dup
    begin
      yield self
    rescue ex : Error
      @undo_stack = undo
      @redo_stack = redo
      restore(snap)
      raise ex
    end
    self
  end

  def preview(& : Session ->) : Preview
    clone = Session.new(@source, @language, check: @check)
    yield clone
    Preview.new(clone.source, Diff.unified(@source, clone.source), clone.edit_count)
  end

  def clear_extracted : self
    @extracted.clear
    self
  end

  def find(query_source : String, within : String? = nil) : Array(TreeSitter::Match)
    scoped_matches(TreeSitter::Query.new(@language, query_source), within)
  end

  def node_at(row : Int32, column : Int32) : TreeSitter::Node?
    point = LibTreeSitter::Point.new(row: row.to_u32, column: column.to_u32)
    node  = TreeSitter::Node.new(LibTreeSitter.ts_node_descendant_for_point_range(@tree.root.raw, point, point), @tree)
    node.null? ? nil : node
  end

  def outline(depth : Int32 = 2) : Array(OutlineEntry)
    entries = [] of OutlineEntry
    collect_outline(@tree.root, depth, entries)
    entries
  end

  def expect(query_source : String, count : Int32? = nil, min : Int32? = nil, max : Int32? = nil) : self
    raise ArgumentError.new("expect needs at least one of count:, min:, or max:") if count.nil? && min.nil? && max.nil?
    found = find(query_source).size
    raise Error.new("expected #{count} match(es), found #{found}") if count && found != count
    raise Error.new("expected at least #{min} match(es), found #{found}") if min && found < min
    raise Error.new("expected at most #{max} match(es), found #{found}") if max && found > max
    self
  end

  def replace(query_source : String, capture : String | Array(String), replacement : String, *, skip : Int32 = 0, limit : Int32? = nil, within : String? = nil, check : Bool? = nil) : self
    replace(query_source, capture, skip: skip, limit: limit, within: within, check: check) { replacement }
  end

  def replace(query_source : String, capture : String | Array(String), *, skip : Int32 = 0, limit : Int32? = nil, within : String? = nil, check : Bool? = nil, &block : TreeSitter::Match -> String) : self
    names = normalize(capture)
    run(query_source, skip, limit, check_flag(check), label(names), within: within) do |matches, src, _tree|
      edits = [] of Edit
      seen  = false
      matches.each do |match|
        replacement = block.call(match)
        match.captures.each do |cap|
          next unless names.includes?(cap.name)
          seen = true
          edits << Edit.new(cap.node.start_byte, cap.node.end_byte, replacement)
        end
      end
      {edits, seen, [] of String}
    end
  end

  def delete(query_source : String, capture : String | Array(String), *, skip : Int32 = 0, limit : Int32? = nil, within : String? = nil, check : Bool? = nil) : self
    names = normalize(capture)
    run(query_source, skip, limit, check_flag(check), label(names), within: within) do |matches, src, _tree|
      edits = [] of Edit
      seen  = false
      matches.each do |match|
        ranges = [] of Tuple(Int32, Int32)
        match.captures.each do |cap|
          next unless names.includes?(cap.name)
          ranges << {cap.node.start_byte, cap.node.end_byte}
        end
        next if ranges.empty?
        seen = true
        ranges.sort!
        cluster_start, cluster_stop = ranges[0]
        ranges[1..].each do |(r_start, r_stop)|
          if r_start <= cluster_stop || gap_blank?(src, cluster_stop, r_start)
            cluster_stop = {cluster_stop, r_stop}.max
          else
            edits << Edit.new(*absorb_line(cluster_start, cluster_stop, src), "")
            cluster_start, cluster_stop = r_start, r_stop
          end
        end
        edits << Edit.new(*absorb_line(cluster_start, cluster_stop, src), "")
      end
      {edits, seen, [] of String}
    end
  end

  def insert(query_source : String, capture : String | Array(String), text : String, *, before : Bool = false, skip : Int32 = 0, limit : Int32? = nil, within : String? = nil, check : Bool? = nil) : self
    insert(query_source, capture, before: before, skip: skip, limit: limit, within: within, check: check) { text }
  end

  def insert(query_source : String, capture : String | Array(String), *, before : Bool = false, skip : Int32 = 0, limit : Int32? = nil, within : String? = nil, check : Bool? = nil, &block : TreeSitter::Match -> String) : self
    names = normalize(capture)
    run(query_source, skip, limit, check_flag(check), label(names), within: within) do |matches, src, _tree|
      edits = [] of Edit
      seen  = false
      matches.each do |match|
        text = block.call(match)
        match.captures.each do |cap|
          next unless names.includes?(cap.name)
          seen = true
          node = cap.node
          if before
            edits << Edit.new(node.start_byte, node.start_byte, text)
          else
            edits << Edit.new(node.end_byte, node.end_byte, text)
          end
        end
      end
      {edits, seen, [] of String}
    end
  end

  def wrap(query_source : String, capture : String | Array(String), *, prefix : String? = nil, suffix : String? = nil, skip : Int32 = 0, limit : Int32? = nil, within : String? = nil, check : Bool? = nil) : self
    raise Error.new("wrap needs a prefix and/or suffix") if prefix.nil? && suffix.nil?
    names = normalize(capture)
    run(query_source, skip, limit, check_flag(check), label(names), within: within) do |matches, src, _tree|
      edits = [] of Edit
      seen  = false
      matches.each do |match|
        match.captures.each do |cap|
          next unless names.includes?(cap.name)
          seen = true
          node = cap.node
          edits << Edit.new(node.start_byte, node.start_byte, prefix) if prefix
          edits << Edit.new(node.end_byte, node.end_byte, suffix) if suffix
        end
      end
      {edits, seen, [] of String}
    end
  end

  def swap(query_source : String, first : String, second : String, *, skip : Int32 = 0, limit : Int32? = nil, within : String? = nil, check : Bool? = nil) : self
    run(query_source, skip, limit, check_flag(check), label([first, second]), within: within) do |matches, src, _tree|
      edits = [] of Edit
      seen  = false
      matches.each do |match|
        a = nodes_for(match, first)
        b = nodes_for(match, second)
        next unless a.size == 1 && b.size == 1
        seen = true
        edits << Edit.new(a[0].start_byte, a[0].end_byte, b[0].text(src))
        edits << Edit.new(b[0].start_byte, b[0].end_byte, a[0].text(src))
      end
      {edits, seen, [] of String}
    end
  end

  def move(query_source : String, from : String, to : String, *, position : Symbol = :after, skip : Int32 = 0, limit : Int32? = nil, within : String? = nil, check : Bool? = nil) : self
    validate_position(position)
    run(query_source, skip, limit, check_flag(check), label([from, to]), within: within) do |matches, src, _tree|
      edits = [] of Edit
      seen  = false
      matches.each do |match|
        from_nodes = nodes_for(match, from)
        to_nodes   = nodes_for(match, to)
        next unless from_nodes.size == 1 && to_nodes.size == 1
        seen  = true
        node  = from_nodes[0]
        point = position == :before ? to_nodes[0].start_byte : to_nodes[0].end_byte
        next if point >= node.start_byte && point <= node.end_byte
        del_start, del_end = deletion_range(node, src)
        next if point >= del_start && point <= del_end
        edits << Edit.new(del_start, del_end, "")
        edits << Edit.new(point, point, insertion_text(node.text(src), to_nodes[0], position, src))
      end
      {edits, seen, [] of String}
    end
  end

  def reorder(query_source : String, capture : String | Array(String), to_query : String, to_capture : String, *, position : Symbol = :after, skip : Int32 = 0, limit : Int32? = nil, within : String? = nil, check : Bool? = nil) : self
    validate_position(position)
    names = normalize(capture)
    run(query_source, skip, limit, check_flag(check), label(names), within: within) do |matches, src, tree|
      target_query = TreeSitter::Query.new(@language, to_query)
      target_nodes = [] of TreeSitter::Node
      target_query.matches(tree.root, src).each do |match|
        target_nodes.concat(nodes_for(match, to_capture))
      end
      unless target_nodes.size == 1
        raise Error.new("destination query matched #{target_nodes.size} node(s); it must match exactly one (refine the query or add predicates)")
      end
      point = position == :before ? target_nodes[0].start_byte : target_nodes[0].end_byte
      edits = [] of Edit
      seen  = false
      matches.each do |match|
        match.captures.each do |cap|
          next unless names.includes?(cap.name)
          seen = true
          node = cap.node
          next if point >= node.start_byte && point <= node.end_byte
          del_start, del_end = deletion_range(node, src)
          next if point >= del_start && point <= del_end
          edits << Edit.new(del_start, del_end, "")
          edits << Edit.new(point, point, insertion_text(node.text(src), target_nodes[0], position, src))
        end
      end
      {edits, seen, [] of String}
    end
  end

  def sort(query_source : String, capture : String | Array(String), *, reverse : Bool = false, skip : Int32 = 0, limit : Int32? = nil, within : String? = nil, check : Bool? = nil) : self
    names = normalize(capture)
    run(query_source, skip, limit, check_flag(check), label(names), within: within) do |matches, src, _tree|
      nodes = [] of TreeSitter::Node
      seen  = false
      matches.each do |match|
        match.captures.each do |cap|
          next unless names.includes?(cap.name)
          seen = true
          nodes << cap.node
        end
      end
      edits = [] of Edit
      group_by_parent(nodes).each do |group|
        next if group.size < 2
        texts  = group.map { |n| n.text(src) }
        sorted = texts.sort
        sorted.reverse! if reverse
        group.sort_by(&.start_byte).each_with_index do |node, i|
          edits << Edit.new(node.start_byte, node.end_byte, sorted[i]) unless node.text(src) == sorted[i]
        end
      end
      {edits, seen, [] of String}
    end
  end

  def dedupe(query_source : String, capture : String | Array(String), *, skip : Int32 = 0, limit : Int32? = nil, within : String? = nil, check : Bool? = nil) : self
    names = normalize(capture)
    run(query_source, skip, limit, check_flag(check), label(names), within: within) do |matches, src, _tree|
      nodes = [] of TreeSitter::Node
      seen  = false
      matches.each do |match|
        match.captures.each do |cap|
          next unless names.includes?(cap.name)
          seen = true
          nodes << cap.node
        end
      end
      edits = [] of Edit
      group_by_parent(nodes).each do |group|
        encountered = Set(String).new
        group.sort_by(&.start_byte).each do |node|
          text = node.text(src)
          if encountered.includes?(text)
            del_start, del_end = deletion_range(node, src)
            edits << Edit.new(del_start, del_end, "")
          else
            encountered << text
          end
        end
      end
      {edits, seen, [] of String}
    end
  end

  def unwrap(query_source : String, outer : String, inner : String, *, skip : Int32 = 0, limit : Int32? = nil, within : String? = nil, check : Bool? = nil) : self
    run(query_source, skip, limit, check_flag(check), label([outer, inner]), within: within) do |matches, src, _tree|
      edits = [] of Edit
      seen  = false
      matches.each do |match|
        outer_nodes = nodes_for(match, outer)
        inner_nodes = nodes_for(match, inner)
        next unless outer_nodes.size == 1 && inner_nodes.size == 1
        seen = true
        edits << Edit.new(outer_nodes[0].start_byte, outer_nodes[0].end_byte, inner_nodes[0].text(src))
      end
      {edits, seen, [] of String}
    end
  end

  def overwrite(query_source : String, target : String, source_capture : String, *, skip : Int32 = 0, limit : Int32? = nil, within : String? = nil, check : Bool? = nil) : self
    run(query_source, skip, limit, check_flag(check), label([target, source_capture]), within: within) do |matches, src, _tree|
      edits = [] of Edit
      seen  = false
      matches.each do |match|
        target_nodes = nodes_for(match, target)
        source_nodes = nodes_for(match, source_capture)
        next unless target_nodes.size == 1 && source_nodes.size == 1
        seen = true
        edits << Edit.new(target_nodes[0].start_byte, target_nodes[0].end_byte, source_nodes[0].text(src))
      end
      {edits, seen, [] of String}
    end
  end

  def duplicate(query_source : String, capture : String | Array(String), *, position : Symbol = :after, skip : Int32 = 0, limit : Int32? = nil, within : String? = nil, check : Bool? = nil) : self
    validate_position(position)
    names = normalize(capture)
    run(query_source, skip, limit, check_flag(check), label(names), within: within) do |matches, src, _tree|
      edits = [] of Edit
      seen  = false
      matches.each do |match|
        match.captures.each do |cap|
          next unless names.includes?(cap.name)
          seen  = true
          node  = cap.node
          point = position == :before ? node.start_byte : node.end_byte
          edits << Edit.new(point, point, insertion_text(node.text(src), node, position, src))
        end
      end
      {edits, seen, [] of String}
    end
  end

  def extract(query_source : String, capture : String | Array(String), replacement : String, *, skip : Int32 = 0, limit : Int32? = nil, within : String? = nil, check : Bool? = nil) : self
    extract(query_source, capture, skip: skip, limit: limit, within: within, check: check) { replacement }
  end

  def extract(query_source : String, capture : String | Array(String), *, skip : Int32 = 0, limit : Int32? = nil, within : String? = nil, check : Bool? = nil, &block : TreeSitter::Match -> String) : self
    names = normalize(capture)
    run(query_source, skip, limit, check_flag(check), label(names), within: within) do |matches, src, _tree|
      edits = [] of Edit
      seen  = false
      ext   = [] of String
      matches.each do |match|
        replacement = block.call(match)
        match.captures.each do |cap|
          next unless names.includes?(cap.name)
          seen = true
          ext << cap.node.text(src)
          edits << Edit.new(cap.node.start_byte, cap.node.end_byte, replacement)
        end
      end
      {edits, seen, ext}
    end
  end

  def comment(query_source : String, capture : String | Array(String), *, prefix : String? = nil, suffix : String? = nil, skip : Int32 = 0, limit : Int32? = nil, within : String? = nil, check : Bool? = nil) : self
    p, s = comment_delimiters(prefix, suffix)
    wrap(query_source, capture, prefix: "#{p} ", suffix: s.empty? ? nil : " #{s}", skip: skip, limit: limit, within: within, check: check)
  end

  def uncomment(query_source : String, capture : String | Array(String), *, prefix : String? = nil, suffix : String? = nil, skip : Int32 = 0, limit : Int32? = nil, within : String? = nil, check : Bool? = nil) : self
    p, s = comment_delimiters(prefix, suffix)
    transform_captures(query_source, capture, skip, limit, within, check) do |text|
      body = text
      if body.starts_with?(p)
        body = body[p.size..]
        body = body[1..] if body.starts_with?(' ')
      end
      if !s.empty? && body.ends_with?(s)
        body = body[...body.size - s.size]
        body = body[...body.size - 1] if body.ends_with?(' ')
      end
      body
    end
  end

  def indent(query_source : String, capture : String | Array(String), *, by : Int32 = 2, skip : Int32 = 0, limit : Int32? = nil, within : String? = nil, check : Bool? = nil) : self
    pad = " " * by
    shift_lines(query_source, capture, skip, limit, within, check) { |line| line.strip.empty? ? line : pad + line }
  end

  def outdent(query_source : String, capture : String | Array(String), *, by : Int32 = 2, skip : Int32 = 0, limit : Int32? = nil, within : String? = nil, check : Bool? = nil) : self
    shift_lines(query_source, capture, skip, limit, within, check) do |line|
      i = 0
      while i < by && i < line.size && line[i] == ' '
        i += 1
      end
      line[i..]
    end
  end

  def toggle(query_source : String, capture : String | Array(String), a : String, b : String, *, skip : Int32 = 0, limit : Int32? = nil, within : String? = nil, check : Bool? = nil) : self
    transform_captures(query_source, capture, skip, limit, within, check) do |text|
      case text
      when a then b
      when b then a
      else        text
      end
    end
  end

  def rename(query_source : String, capture : String, to : String, *, scope : Array(String)? = nil, skip : Int32 = 0, limit : Int32? = nil, within : String? = nil, check : Bool? = nil) : self
    scope_types = scope || Languages.scope_types(@language.name)
    run(query_source, skip, limit, check_flag(check), label([capture]), within: within) do |matches, src, tree|
      edits = [] of Edit
      seen  = false
      matches.each do |match|
        match.captures.each do |cap|
          next unless cap.name == capture
          seen       = true
          node       = cap.node
          original   = node.text(src)
          scope_node = enclosing_scope(node, scope_types) || tree.root
          collect_renames(scope_node, node.type, original, to, src, edits)
        end
      end
      {edits, seen, [] of String}
    end
  end

  private def shift_lines(query_source : String, capture : String | Array(String), skip : Int32, limit : Int32?, within : String?, check : Bool?, &block : String -> String) : self
    names = normalize(capture)
    run(query_source, skip, limit, check_flag(check), label(names), within: within) do |matches, src, _tree|
      edits = [] of Edit
      seen  = false
      matches.each do |match|
        match.captures.each do |cap|
          next unless names.includes?(cap.name)
          node  = cap.node
          start = node.start_byte
          while start > 0 && src.byte_at(start - 1) != 0x0A
            start -= 1
          end
          next unless gap_blank?(src, start, node.start_byte)
          text     = src.byte_slice(start, node.end_byte - start)
          new_text = String.build { |io| text.each_line { |line| io << block.call(line) } }
          next if new_text == text
          seen = true
          edits << Edit.new(start, node.end_byte, new_text)
        end
      end
      {edits, seen, [] of String}
    end
  end

  private def transform_captures(query_source : String, capture : String | Array(String), skip : Int32, limit : Int32?, within : String?, check : Bool?, & : String -> String) : self
    names = normalize(capture)
    run(query_source, skip, limit, check_flag(check), label(names), within: within) do |matches, src, _tree|
      edits = [] of Edit
      seen  = false
      matches.each do |match|
        match.captures.each do |cap|
          next unless names.includes?(cap.name)
          text     = cap.node.text(src)
          new_text = yield text
          next if new_text == text
          seen = true
          edits << Edit.new(cap.node.start_byte, cap.node.end_byte, new_text)
        end
      end
      {edits, seen, [] of String}
    end
  end

  private def comment_delimiters(prefix : String?, suffix : String?) : Tuple(String, String)
    return {prefix, suffix || ""} if prefix
    name = @language.name || raise Error.new("cannot infer comment delimiters for this language; pass explicit prefix:/suffix:")
    Languages.comment_tokens(name)
  end

  private def check_flag(local : Bool?) : Bool
    local.nil? ? @check : local
  end

  private def normalize(capture : String | Array(String)) : Array(String)
    capture.is_a?(String) ? [capture] : capture
  end

  private def label(names : Array(String)) : String
    names.map { |n| "@#{n}" }.join(", ")
  end

  private def validate_position(position : Symbol) : Nil
    unless position == :before || position == :after
      raise Error.new("invalid position :#{position} (expected :before or :after)")
    end
  end

  private def run(query_source : String, skip : Int32, limit : Int32?, check : Bool, label : String, within : String? = nil, & : Array(TreeSitter::Match), String, TreeSitter::Tree -> Tuple(Array(Edit), Bool, Array(String))) : self
    prev    = snapshot
    query   = TreeSitter::Query.new(@language, query_source)
    matches = scoped_matches(query, within)
    matches = matches[skip..] if skip > 0
    matches = matches.first(limit) if limit

    edits, seen, extracted_texts = yield matches, @source, @tree

    raise NoMatchesError.new("no matches for capture(s) #{label}") unless seen
    @last_edits = edits.uniq
    return self if edits.empty?

    result = Editor.apply(@source, edits)

    input_edit = Editor.input_edit(@source, result, edits)
    @tree.edit(input_edit)
    new_tree = @parser.parse(result, @tree)

    if check && new_tree.has_error?
      raise syntax_guard_error("the edit would introduce syntax errors", new_tree, result)
    end

    @tree   = new_tree
    @source = result
    @edit_count += edits.uniq.size
    @extracted.concat(extracted_texts)
    @undo_stack << prev
    @redo_stack.clear

    self
  end

  private def scoped_matches(query : TreeSitter::Query, within : String?) : Array(TreeSitter::Match)
    return query.matches(@tree.root, @source) unless within
    scope_query   = TreeSitter::Query.new(@language, within)
    scope_matches = scope_query.matches(@tree.root, @source)
    raise NoMatchesError.new("no scope matches for within query: #{within}") if scope_matches.empty?
    matches = [] of TreeSitter::Match
    scope_matches.each do |scope_match|
      if cap = scope_match.captures.first?
        matches.concat(query.matches(cap.node, @source))
      end
    end
    matches
  end

  private def enclosing_scope(node : TreeSitter::Node, types : Array(String)?) : TreeSitter::Node?
    return nil unless types
    current = node.parent
    while current
      return current if types.includes?(current.type)
      current = current.parent
    end
    nil
  end

  private def collect_renames(node : TreeSitter::Node, type : String, original : String, to : String, src : String, edits : Array(Edit)) : Nil
    if node.type == type && node.text(src) == original
      edits << Edit.new(node.start_byte, node.end_byte, to)
      return
    end
    node.named_child_count.times do |i|
      if child = node.named_child(i)
        collect_renames(child, type, original, to, src, edits)
      end
    end
  end

  private def nodes_for(match : TreeSitter::Match, name : String) : Array(TreeSitter::Node)
    match.captures.select { |c| c.name == name }.map(&.node)
  end

  private def collect_outline(node : TreeSitter::Node, depth : Int32, entries : Array(OutlineEntry), level : Int32 = 1) : Nil
    return if level > depth
    node.named_child_count.times do |i|
      child = node.named_child(i)
      next unless child
      name  = (child.field("name") || child.field("key")).try(&.text(@source))
      point = child.start_point
      entries << OutlineEntry.new(child.type, name, point.row.to_i + 1, point.column.to_i + 1) if level == 1 || name
      collect_outline(child, depth, entries, level + 1)
    end
  end

  private def syntax_guard_error(message : String, tree : TreeSitter::Tree, source : String) : SyntaxGuardError
    node = tree.first_error
    return SyntaxGuardError.new(message) unless node
    point   = node.start_point
    line    = point.row.to_i + 1
    column  = point.column.to_i + 1
    excerpt = source.each_line.to_a[point.row.to_i]?.try(&.strip) || ""
    SyntaxGuardError.new(%(#{message} (line #{line}, column #{column}: "#{excerpt}")), line, column, excerpt)
  end

  private def group_by_parent(nodes : Array(TreeSitter::Node)) : Array(Array(TreeSitter::Node))
    groups = Hash(Tuple(Int32, Int32), Array(TreeSitter::Node)).new
    nodes.each do |node|
      parent = node.parent
      key    = parent ? {parent.start_byte, parent.end_byte} : {node.start_byte, node.end_byte}
      (groups[key] ||= [] of TreeSitter::Node) << node
    end
    groups.values
  end

  private def child_index(parent : TreeSitter::Node, node : TreeSitter::Node) : Int32?
    parent.child_count.times do |i|
      child = parent.child(i)
      return i if child && child.start_byte == node.start_byte && child.end_byte == node.end_byte
    end
    nil
  end

  private def separator?(node : TreeSitter::Node, source : String) : Bool
    !node.named? && node.text(source).matches?(/\A[,;]\z/)
  end

  private def deletion_range(node : TreeSitter::Node, source : String) : Tuple(Int32, Int32)
    start = node.start_byte
    stop  = node.end_byte
    if (parent = node.parent) && (idx = child_index(parent, node))
      if idx > 0 && (prev = parent.child(idx - 1)) && separator?(prev, source)
        start = prev.start_byte
      elsif (nxt = parent.child(idx + 1)) && separator?(nxt, source)
        stop = nxt.end_byte
        while stop < source.bytesize && (source.byte_at(stop) == 0x20 || source.byte_at(stop) == 0x09)
          stop += 1
        end
      end
    end
    absorb_line(start, stop, source)
  end

  private def gap_blank?(source : String, from : Int32, to : Int32) : Bool
    i = from
    while i < to
      byte = source.byte_at(i)
      return false unless byte == 0x20 || byte == 0x09
      i += 1
    end
    true
  end

  private def absorb_line(start : Int32, stop : Int32, source : String) : Tuple(Int32, Int32)
    return {start, stop} unless stop < source.bytesize && source.byte_at(stop) == 0x0A
    line_start = start
    while line_start > 0 && source.byte_at(line_start - 1) != 0x0A
      line_start -= 1
    end
    i = line_start
    while i < start && (source.byte_at(i) == 0x20 || source.byte_at(i) == 0x09)
      i += 1
    end
    return {line_start, stop + 1} if i == start
    {start, stop}
  end

  private def insertion_text(text : String, target : TreeSitter::Node, pos : Symbol, source : String) : String
    parent = target.parent
    if parent && (idx = child_index(parent, target))
      if (nxt = parent.child(idx + 1)) && separator?(nxt, source)
        stop  = parent.child(idx + 2).try(&.start_byte) || nxt.end_byte
        block = source.byte_slice(nxt.start_byte, stop - nxt.start_byte)
        return pos == :before ? text + block : block + text
      end
      if idx > 0 && (prev = parent.child(idx - 1)) && separator?(prev, source)
        block = source.byte_slice(prev.start_byte, target.start_byte - prev.start_byte)
        return pos == :before ? text + block : block + text
      end
    end
    pos == :before ? text + "\n" : "\n" + text
  end
end
