# src/ts-edit.cr
require "./ts-edit/errors"
require "./ts-edit/tree_sitter"
require "./ts-edit/editor"
require "./ts-edit/languages"
require "./ts-edit/ops"

module TsEdit
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify }}
end
