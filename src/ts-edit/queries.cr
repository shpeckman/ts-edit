# src/ts-edit/queries.cr
require "./errors"

module TsEdit::Queries
  extend self

  def load(path : String) : String
    raise Error.new("query file not found: #{path}") unless File.exists?(path)
    File.read(path)
  end
end
