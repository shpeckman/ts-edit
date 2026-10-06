# spec/file_helpers_spec.cr
require "./spec_helper"

describe TsEdit::Session do
  it "loads a session from a file and infers the language" do
    path = File.tempname("ts_edit", ".json")
    File.write(path, %({"b": 2, "a": 1}))
    begin
      session = TsEdit::Session.from_file(path)
      session.path.should eq path
      session.source.should eq %({"b": 2, "a": 1})
    ensure
      File.delete(path) if File.exists?(path)
    end
  end

  it "writes the source to an explicit path or the session path" do
    src  = File.tempname("ts_edit", ".json")
    dest = File.tempname("ts_edit", ".json")
    File.write(src, %({"b": 2, "a": 1}))
    begin
      session = TsEdit::Session.from_file(src)
      session.sort("(pair) @p", "p")
      session.write(dest)
      File.read(dest).should eq %({"a": 1, "b": 2})
      session.write
      File.read(src).should eq %({"a": 1, "b": 2})
    ensure
      File.delete(src) if File.exists?(src)
      File.delete(dest) if File.exists?(dest)
    end
  end

  it "raises when writing without any path" do
    session = TsEdit::Session.new(%({"a": 1}), lang("json"))
    expect_raises(TsEdit::Error, /no path/) { session.write }
  end

  it "processes a file in place only when the source changed" do
    path = File.tempname("ts_edit", ".json")
    File.write(path, %({"b": 2, "a": 1}))
    begin
      TsEdit::Session.process(path) do |s|
        s.sort("(pair) @p", "p")
      end
      File.read(path).should eq %({"a": 1, "b": 2})

      mtime = File.info(path).modification_time
      TsEdit::Session.process(path) { |s| s }
      File.info(path).modification_time.should eq mtime
    ensure
      File.delete(path) if File.exists?(path)
    end
  end
end
