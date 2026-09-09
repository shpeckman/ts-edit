# src/tree_sitter/lib.cr
@[Link(ldflags: "#{__DIR__}/../../vendor/build/libtree-sitter.a #{__DIR__}/../../vendor/build/json.o #{__DIR__}/../../vendor/build/crystal_parser.o #{__DIR__}/../../vendor/build/crystal_scanner.o #{__DIR__}/../../vendor/build/crystal_unicode.o")]
lib LibTreeSitter
  alias TSParser = Void*
  alias TSTree = Void*
  alias TSLanguage = Void*
  alias TSQuery = Void*
  alias TSQueryCursor = Void*

  struct Point
    row : UInt32
    column : UInt32
  end

  struct Node
    context : UInt32[4]
    id : Void*
    tree : TSTree
  end

  struct QueryCapture
    node : Node
    index : UInt32
  end

  struct QueryMatch
    id : UInt32
    pattern_index : UInt16
    capture_count : UInt16
    captures : QueryCapture*
  end

  enum QueryPredicateStepType
    Done
    Capture
    String
  end

  struct QueryPredicateStep
    type : QueryPredicateStepType
    value_id : UInt32
  end

  enum QueryError
    None      = 0
    Syntax    = 1
    NodeType  = 2
    Field     = 3
    Capture   = 4
    Structure = 5
    Language  = 6
  end

  fun ts_parser_new : TSParser
  fun ts_parser_delete(parser : TSParser)
  fun ts_parser_set_language(parser : TSParser, language : TSLanguage) : Bool
  fun ts_parser_parse_string(parser : TSParser, old_tree : TSTree, string : UInt8*, length : UInt32) : TSTree

  fun ts_tree_root_node(tree : TSTree) : Node
  fun ts_tree_delete(tree : TSTree)

  fun ts_node_type(node : Node) : UInt8*
  fun ts_node_start_byte(node : Node) : UInt32
  fun ts_node_end_byte(node : Node) : UInt32
  fun ts_node_is_null(node : Node) : Bool
  fun ts_node_is_named(node : Node) : Bool
  fun ts_node_is_error(node : Node) : Bool
  fun ts_node_has_error(node : Node) : Bool
  fun ts_node_child_count(node : Node) : UInt32
  fun ts_node_named_child_count(node : Node) : UInt32
  fun ts_node_child(node : Node, index : UInt32) : Node
  fun ts_node_named_child(node : Node, index : UInt32) : Node
  fun ts_node_parent(node : Node) : Node
  fun ts_node_string(node : Node) : UInt8*

  fun ts_query_new(language : TSLanguage, source : UInt8*, source_len : UInt32, error_offset : UInt32*, error_type : QueryError*) : TSQuery
  fun ts_query_delete(query : TSQuery)
  fun ts_query_capture_count(query : TSQuery) : UInt32
  fun ts_query_capture_name_for_id(query : TSQuery, index : UInt32, length : UInt32*) : UInt8*
  fun ts_query_string_value_for_id(query : TSQuery, index : UInt32, length : UInt32*) : UInt8*
  fun ts_query_predicates_for_pattern(query : TSQuery, pattern_index : UInt32, step_count : UInt32*) : QueryPredicateStep*

  fun ts_query_cursor_new : TSQueryCursor
  fun ts_query_cursor_delete(cursor : TSQueryCursor)
  fun ts_query_cursor_exec(cursor : TSQueryCursor, query : TSQuery, node : Node)
  fun ts_query_cursor_next_match(cursor : TSQueryCursor, match : QueryMatch*) : Bool

  fun tree_sitter_json : TSLanguage
  fun tree_sitter_crystal : TSLanguage
end
