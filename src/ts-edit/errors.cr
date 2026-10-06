# src/ts-edit/errors.cr
module TsEdit
  class Error < Exception
  end

  class NoMatchesError < Error
  end

  class ConflictError < Error
  end

  class SyntaxGuardError < Error
    getter line    : Int32?
    getter column  : Int32?
    getter excerpt : String?

    def initialize(message : String, @line : Int32? = nil, @column : Int32? = nil, @excerpt : String? = nil)
      super(message)
    end
  end
end
