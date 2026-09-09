# spec/spec_helper.cr
require "spec"
require "../src/ts-edit"

def lang(name : String) : TsEdit::TreeSitter::Language
  TsEdit::Languages.fetch(name)
end
