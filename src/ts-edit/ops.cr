# src/ts-edit/ops.cr
require "set"
require "./errors"
require "./tree_sitter"
require "./editor"

module TsEdit
  module Ops
    extend self

    struct Result
      getter source : String
      getter edits  : Int32

      def initialize(@source : String, @edits : Int32)
      end
    end

    def replace(source : String, language : TreeSitter::Language, query : String, capture : String | Array(String), replacement : String, *, skip : Int32 = 0, limit : Int32? = nil, check : Bool = true) : Result
      names = normalize(capture)
      run(source, language, query, skip, limit, check, label(names)) do |matches, src, _tree|
        edits = [] of Edit
        seen  = false
        matches.each do |match|
          match.captures.each do |cap|
            next unless names.includes?(cap.name)
            seen = true
            edits << Edit.new(cap.node.start_byte, cap.node.end_byte, replacement)
          end
        end
        {edits, seen}
      end
    end

    def delete(source : String, language : TreeSitter::Language, query : String, capture : String | Array(String), *, skip : Int32 = 0, limit : Int32? = nil, check : Bool = true) : Result
      names = normalize(capture)
      run(source, language, query, skip, limit, check, label(names)) do |matches, src, _tree|
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
        {edits, seen}
      end
    end

    def insert(source : String, language : TreeSitter::Language, query : String, capture : String | Array(String), text : String, *, before : Bool = false, skip : Int32 = 0, limit : Int32? = nil, check : Bool = true) : Result
      names = normalize(capture)
      run(source, language, query, skip, limit, check, label(names)) do |matches, src, _tree|
        edits = [] of Edit
        seen  = false
        matches.each do |match|
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
        {edits, seen}
      end
    end

    def wrap(source : String, language : TreeSitter::Language, query : String, capture : String | Array(String), *, prefix : String? = nil, suffix : String? = nil, skip : Int32 = 0, limit : Int32? = nil, check : Bool = true) : Result
      raise Error.new("wrap needs a prefix and/or suffix") if prefix.nil? && suffix.nil?
      names = normalize(capture)
      run(source, language, query, skip, limit, check, label(names)) do |matches, src, _tree|
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
        {edits, seen}
      end
    end

    def swap(source : String, language : TreeSitter::Language, query : String, first : String, second : String, *, skip : Int32 = 0, limit : Int32? = nil, check : Bool = true) : Result
      run(source, language, query, skip, limit, check, label([first, second])) do |matches, src, _tree|
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
        {edits, seen}
      end
    end

    def move(source : String, language : TreeSitter::Language, query : String, from : String, to : String, *, position : Symbol = :after, skip : Int32 = 0, limit : Int32? = nil, check : Bool = true) : Result
      validate_position(position)
      run(source, language, query, skip, limit, check, label([from, to])) do |matches, src, _tree|
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
        {edits, seen}
      end
    end

    def reorder(source : String, language : TreeSitter::Language, query : String, capture : String | Array(String), to_query : String, to_capture : String, *, position : Symbol = :after, skip : Int32 = 0, limit : Int32? = nil, check : Bool = true) : Result
      validate_position(position)
      names = normalize(capture)
      run(source, language, query, skip, limit, check, label(names)) do |matches, src, tree|
        target_query = TreeSitter::Query.new(language, to_query)
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
        {edits, seen}
      end
    end

    def sort(source : String, language : TreeSitter::Language, query : String, capture : String | Array(String), *, reverse : Bool = false, skip : Int32 = 0, limit : Int32? = nil, check : Bool = true) : Result
      names = normalize(capture)
      run(source, language, query, skip, limit, check, label(names)) do |matches, src, _tree|
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
        {edits, seen}
      end
    end

    def dedupe(source : String, language : TreeSitter::Language, query : String, capture : String | Array(String), *, skip : Int32 = 0, limit : Int32? = nil, check : Bool = true) : Result
      names = normalize(capture)
      run(source, language, query, skip, limit, check, label(names)) do |matches, src, _tree|
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
        {edits, seen}
      end
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

    private def run(source : String, language : TreeSitter::Language, query_source : String, skip : Int32, limit : Int32?, check : Bool, label : String, & : Array(TreeSitter::Match), String, TreeSitter::Tree -> Tuple(Array(Edit), Bool)) : Result
      parser  = TreeSitter::Parser.new(language)
      tree    = parser.parse(source)
      query   = TreeSitter::Query.new(language, query_source)
      matches = query.matches(tree.root, source)
      matches = matches[skip..] if skip > 0
      matches = matches.first(limit) if limit
      edits, seen = yield matches, source, tree
      raise NoMatchesError.new("no matches for capture(s) #{label}") unless seen
      return Result.new(source, 0) if edits.empty?
      result = Editor.apply(source, edits)
      if check
        input_edit = Editor.input_edit(source, result, edits)
        tree.edit(input_edit)
        new_tree = parser.parse(result, tree)
        raise SyntaxGuardError.new("the edit would introduce syntax errors") if new_tree.has_error?
      end
      Result.new(result, edits.uniq.size)
    end

    private def nodes_for(match : TreeSitter::Match, name : String) : Array(TreeSitter::Node)
      match.captures.select { |c| c.name == name }.map(&.node)
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
end
