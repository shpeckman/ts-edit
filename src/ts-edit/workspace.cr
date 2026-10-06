# src/ts-edit/workspace.cr
require "./errors"
require "./session"

class TsEdit::Workspace
  getter sessions : Hash(String, Session) = {} of String => Session

  @originals : Hash(String, String) = {} of String => String

  def add(path : String, check : Bool = true) : Session
    key     = File.expand_path(path)
    session = Session.from_file(key, check: check)
    @sessions[key] = session
    @originals[key] = session.source
    session
  end

  def add_glob(pattern : String) : self
    Dir.glob(pattern).sort.each { |path| add(path) }
    self
  end

  def [](path : String) : Session
    self[path]? || raise Error.new("no session for '#{path}'")
  end

  def []?(path : String) : Session?
    @sessions[File.expand_path(path)]?
  end

  def each(& : Session ->) : Nil
    @sessions.each_value { |session| yield session }
  end

  def dirty : Array(String)
    @sessions.select { |path, session| session.source != @originals[path] }.keys
  end

  def write_all : self
    dirty.each do |path|
      @sessions[path].write
      @originals[path] = @sessions[path].source
    end
    self
  end
end
