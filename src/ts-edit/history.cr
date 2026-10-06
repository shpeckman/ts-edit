# src/ts-edit/history.cr
require "./errors"

class TsEdit::Session
  struct Snapshot
    getter source     : String
    getter edit_count : Int32
    getter extracted  : Array(String)

    def initialize(@source : String, @edit_count : Int32, @extracted : Array(String))
    end
  end

  def undo : self
    raise Error.new("nothing to undo") unless can_undo?
    @redo_stack << snapshot
    restore(@undo_stack.pop)
    self
  end

  def redo : self
    raise Error.new("nothing to redo") unless can_redo?
    @undo_stack << snapshot
    restore(@redo_stack.pop)
    self
  end

  def can_undo? : Bool
    !@undo_stack.empty?
  end

  def can_redo? : Bool
    !@redo_stack.empty?
  end

  def history_size : Int32
    @undo_stack.size
  end

  private def snapshot : Snapshot
    Snapshot.new(@source, @edit_count, @extracted.dup)
  end

  private def restore(snap : Snapshot) : Nil
    @source     = snap.source
    @edit_count = snap.edit_count
    @extracted  = snap.extracted.dup
    @tree       = @parser.parse(@source)
  end
end
