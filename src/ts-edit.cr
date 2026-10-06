# src/ts-edit.cr
require "./ts-edit/errors"
require "./ts-edit/tree_sitter"
require "./ts-edit/editor"
require "./ts-edit/languages"
require "./ts-edit/history"
require "./ts-edit/diff"
require "./ts-edit/queries"
require "./ts-edit/recipes"
require "./ts-edit/session"
require "./ts-edit/workspace"
require "./ts-edit/dispatcher"

module TsEdit
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify }}
end
