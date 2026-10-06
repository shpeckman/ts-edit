# spec/workspace_spec.cr
require "./spec_helper"
require "file_utils"

private def with_tmpdir(& : String ->)
  dir = File.tempname("ts_edit_workspace")
  Dir.mkdir(dir)
  yield dir
ensure
  FileUtils.rm_rf(dir) if dir
end

describe TsEdit::Workspace do
  it "adds files, tracks dirtiness, and writes changes" do
    with_tmpdir do |dir|
      a = File.join(dir, "a.json")
      b = File.join(dir, "b.json")
      File.write(a, %({"x": 1}))
      File.write(b, %({"y": 2}))

      ws = TsEdit::Workspace.new
      ws.add(a).should be_a TsEdit::Session
      ws.add(b)

      ws[a].should be ws.sessions[File.expand_path(a)]
      ws[b]?.should_not be_nil
      ws.dirty.should be_empty

      ws[a].replace("(number) @n", "n", "10")
      ws.dirty.should eq [File.expand_path(a)]
      File.read(a).should eq %({"x": 1})

      ws.write_all.should be ws
      File.read(a).should eq %({"x": 10})
      File.read(b).should eq %({"y": 2})
      ws.dirty.should be_empty
    end
  end

  it "adds files via glob" do
    with_tmpdir do |dir|
      File.write(File.join(dir, "one.json"), %({"a": 1}))
      File.write(File.join(dir, "two.json"), %({"b": 2}))
      ws = TsEdit::Workspace.new
      ws.add_glob(File.join(dir, "*.json")).should be ws
      ws.sessions.size.should eq 2
    end
  end

  it "raises for unknown paths" do
    ws = TsEdit::Workspace.new
    expect_raises(TsEdit::Error, /no session/) { ws["missing.json"] }
    ws["missing.json"]?.should be_nil
  end

  it "iterates sessions" do
    with_tmpdir do |dir|
      File.write(File.join(dir, "one.json"), %({"a": 1}))
      ws = TsEdit::Workspace.new
      ws.add_glob(File.join(dir, "*.json"))
      count = 0
      ws.each { |_s| count += 1 }
      count.should eq 1
    end
  end
end
