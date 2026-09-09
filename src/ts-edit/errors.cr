# src/ts-edit/errors.cr
module TsEdit
  class Error < Exception
  end

  class NoMatchesError < Error
  end

  class ConflictError < Error
  end

  class SyntaxGuardError < Error
  end
end
