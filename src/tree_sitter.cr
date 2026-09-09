# src/tree_sitter.cr
require "./tree_sitter/lib"

module TreeSitter
  class Error < Exception
  end

  class QueryError < Error
    getter offset : UInt32
    getter kind : LibTreeSitter::QueryError

    def initialize(@offset : UInt32, @kind : LibTreeSitter::QueryError)
      super("invalid query at byte #{offset}: #{kind.to_s.downcase}")
    end
  end

  class Language
    getter ptr : LibTreeSitter::TSLanguage

    def initialize(@ptr : LibTreeSitter::TSLanguage)
    end
  end

  class Parser
    @ptr : LibTreeSitter::TSParser

    def initialize(language : Language)
      @ptr = LibTreeSitter.ts_parser_new
      raise Error.new("tree-sitter rejected the language grammar") unless LibTreeSitter.ts_parser_set_language(@ptr, language.ptr)
    end

    def parse(source : String) : Tree
      ptr = LibTreeSitter.ts_parser_parse_string(@ptr, Pointer(Void).null, source, source.bytesize)
      raise Error.new("parsing failed") if ptr.null?
      Tree.new(ptr)
    end

    def finalize
      LibTreeSitter.ts_parser_delete(@ptr)
    end
  end

  class Tree
    getter ptr : LibTreeSitter::TSTree

    def initialize(@ptr : LibTreeSitter::TSTree)
    end

    def root : Node
      Node.new(LibTreeSitter.ts_tree_root_node(@ptr), self)
    end

    def has_error? : Bool
      root.has_error?
    end

    def finalize
      LibTreeSitter.ts_tree_delete(@ptr)
    end
  end

  struct Node
    getter raw : LibTreeSitter::Node
    getter tree : Tree

    def initialize(@raw : LibTreeSitter::Node, @tree : Tree)
    end

    def type : String
      String.new(LibTreeSitter.ts_node_type(@raw))
    end

    def start_byte : Int32
      LibTreeSitter.ts_node_start_byte(@raw).to_i
    end

    def end_byte : Int32
      LibTreeSitter.ts_node_end_byte(@raw).to_i
    end

    def byte_range : Range(Int32, Int32)
      start_byte...end_byte
    end

    def null? : Bool
      LibTreeSitter.ts_node_is_null(@raw)
    end

    def named? : Bool
      LibTreeSitter.ts_node_is_named(@raw)
    end

    def error? : Bool
      LibTreeSitter.ts_node_is_error(@raw)
    end

    def has_error? : Bool
      LibTreeSitter.ts_node_has_error(@raw)
    end

    def child_count : Int32
      LibTreeSitter.ts_node_child_count(@raw).to_i
    end

    def named_child_count : Int32
      LibTreeSitter.ts_node_named_child_count(@raw).to_i
    end

    def child(index : Int) : Node?
      wrap LibTreeSitter.ts_node_child(@raw, index)
    end

    def named_child(index : Int) : Node?
      wrap LibTreeSitter.ts_node_named_child(@raw, index)
    end

    def parent : Node?
      wrap LibTreeSitter.ts_node_parent(@raw)
    end

    def text(source : String) : String
      source.byte_slice(start_byte, end_byte - start_byte)
    end

    def sexp : String
      cstr = LibTreeSitter.ts_node_string(@raw)
      result = String.new(cstr)
      LibC.free(cstr.as(Void*))
      result
    end

    private def wrap(raw : LibTreeSitter::Node) : Node?
      node = Node.new(raw, @tree)
      node.null? ? nil : node
    end
  end

  struct Capture
    getter node : Node
    getter name : String
    getter id : UInt32

    def initialize(@node : Node, @name : String, @id : UInt32)
    end
  end

  struct Match
    getter pattern_index : Int32
    getter captures : Array(Capture)

    def initialize(@pattern_index : Int32, @captures : Array(Capture))
    end

    def [](name : String) : Node?
      captures.find { |c| c.name == name }.try(&.node)
    end
  end

  class Query
    getter capture_names : Array(String)

    def initialize(language : Language, @source : String)
      error_offset = 0_u32
      error_type = LibTreeSitter::QueryError::None
      @ptr = LibTreeSitter.ts_query_new(language.ptr, @source, @source.bytesize, pointerof(error_offset), pointerof(error_type))
      raise QueryError.new(error_offset, error_type) if @ptr.null?
      @capture_names = Array(String).new(LibTreeSitter.ts_query_capture_count(@ptr)) do |i|
        len = 0_u32
        cstr = LibTreeSitter.ts_query_capture_name_for_id(@ptr, i, pointerof(len))
        String.new(cstr, len)
      end
    end

    def matches(node : Node, source : String) : Array(Match)
      cursor = LibTreeSitter.ts_query_cursor_new
      results = [] of Match
      begin
        LibTreeSitter.ts_query_cursor_exec(cursor, @ptr, node.raw)
        raw_match = LibTreeSitter::QueryMatch.new
        while LibTreeSitter.ts_query_cursor_next_match(cursor, pointerof(raw_match))
          captures = Array(Capture).new(raw_match.capture_count.to_i) do |i|
            qc = raw_match.captures[i]
            Capture.new(Node.new(qc.node, node.tree), @capture_names[qc.index], qc.index)
          end
          if predicates_satisfied?(raw_match.pattern_index.to_u32, captures, source)
            results << Match.new(raw_match.pattern_index.to_i, captures)
          end
        end
      ensure
        LibTreeSitter.ts_query_cursor_delete(cursor)
      end
      results
    end

    def finalize
      LibTreeSitter.ts_query_delete(@ptr)
    end

    private def string_value(id : UInt32) : String
      len = 0_u32
      cstr = LibTreeSitter.ts_query_string_value_for_id(@ptr, id, pointerof(len))
      String.new(cstr, len)
    end

    private def predicates_satisfied?(pattern_index : UInt32, captures : Array(Capture), source : String) : Bool
      step_count = 0_u32
      steps = LibTreeSitter.ts_query_predicates_for_pattern(@ptr, pattern_index, pointerof(step_count))
      return true if step_count == 0
      i = 0_u32
      while i < step_count
        step = steps[i]
        break unless step.type.string?
        op = string_value(step.value_id)
        i += 1
        args = [] of String | UInt32
        while i < step_count && !steps[i].type.done?
          arg = steps[i]
          if arg.type.capture?
            args << arg.value_id
          else
            args << string_value(arg.value_id)
          end
          i += 1
        end
        i += 1
        return false unless eval_predicate(op, args, captures, source)
      end
      true
    end

    private def eval_predicate(op : String, args : Array(String | UInt32), captures : Array(Capture), source : String) : Bool
      texts = ->(id : UInt32) { captures.select { |c| c.id == id }.map { |c| c.node.text(source) } }
      case op
      when "eq?", "not-eq?", "any-eq?", "any-not-eq?"
        values = texts.call(args[0].as(UInt32))
        expected = args[1].as(String)
        result = op.starts_with?("any-") ? values.any? { |v| v == expected } : values.all? { |v| v == expected }
        op.includes?("not") ? !result : result
      when "match?", "not-match?", "any-match?", "any-not-match?"
        values = texts.call(args[0].as(UInt32))
        regex = Regex.new(args[1].as(String))
        result = op.starts_with?("any-") ? values.any?(&.matches?(regex)) : values.all?(&.matches?(regex))
        op.includes?("not") ? !result : result
      when "any-of?", "not-any-of?"
        values = texts.call(args[0].as(UInt32))
        options = args[1..].map(&.as(String))
        found = values.any? { |v| options.includes?(v) }
        op.starts_with?("not-") ? !found : found
      else
        true
      end
    rescue ex : IndexError | ArgumentError | Regex::Error
      raise Error.new("malformed predicate ##{op}: #{ex.message}")
    end
  end
end
