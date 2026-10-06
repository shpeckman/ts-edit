# spec/preview_spec.cr
require "./spec_helper"

describe TsEdit::Session do
  json = %({"gamma": 3, "alpha": 1, "beta": 2})

  it "previews edits without mutating the receiver" do
    session = TsEdit::Session.new(json, lang("json"))
    preview = session.preview do |s|
      s.sort("(pair) @p", "p")
    end
    session.source.should eq json
    session.history_size.should eq 0
    preview.source.should eq %({"alpha": 1, "beta": 2, "gamma": 3})
    preview.edit_count.should be > 0
  end

  it "produces a unified diff with a hunk header and +/- lines" do
    session = TsEdit::Session.new(json, lang("json"))
    preview = session.preview do |s|
      s.replace("(number) @n", "n", "0")
    end
    preview.diff.should contain "@@ -1,1 +1,1 @@"
    preview.diff.should contain %(-{"gamma": 3, "alpha": 1, "beta": 2})
    preview.diff.should contain %(+{"gamma": 0, "alpha": 0, "beta": 0})
  end

  it "returns an empty diff when nothing changes" do
    session = TsEdit::Session.new(json, lang("json"))
    preview = session.preview { |s| s }
    preview.diff.should eq ""
    preview.source.should eq json
    preview.edit_count.should eq 0
  end

  it "diffs multi-line sources with context" do
    py      = "def greet(name):\n    return name\n\ndef shout(name):\n    return greet(name).upper()\n"
    session = TsEdit::Session.new(py, lang("python"))
    preview = session.preview do |s|
      s.replace("(function_definition name: (identifier) @n)", "n", "welcome", limit: 1)
    end
    preview.diff.should contain "-def greet(name):"
    preview.diff.should contain "+def welcome(name):"
    preview.diff.should contain " return name"
  end
end
