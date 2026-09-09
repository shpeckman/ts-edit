# src/ts-edit/editor.cr
module TsEdit
  struct Edit
    getter start_byte  : Int32
    getter end_byte    : Int32
    getter replacement : String

    def initialize(@start_byte : Int32, @end_byte : Int32, @replacement : String)
    end

    def ==(other : Edit) : Bool
      start_byte == other.start_byte && end_byte == other.end_byte && replacement == other.replacement
    end

    def hash(hasher)
      {start_byte, end_byte, replacement}.hash(hasher)
    end
  end

  module Editor
    extend self

    def apply(source : String, edits : Array(Edit)) : String
      sorted = edits.uniq.sort_by { |e| {e.start_byte, e.end_byte} }
      sorted.each_cons(2) do |pair|
        a, b = pair
        if b.start_byte < a.end_byte
          raise "conflicting edits: [#{a.start_byte}...#{a.end_byte}] overlaps [#{b.start_byte}...#{b.end_byte}]"
        end
      end
      bytes  = source.to_slice
      io     = IO::Memory.new(bytes.size + sorted.sum(0) { |e| e.replacement.bytesize })
      cursor = 0
      sorted.each do |edit|
        io.write bytes[cursor...edit.start_byte]
        io << edit.replacement
        cursor = edit.end_byte
      end
      io.write bytes[cursor..]
      io.to_s
    end

    def input_edit(source : String, result : String, edits : Array(Edit)) : LibTreeSitter::InputEdit
      sorted     = edits.sort_by { |e| {e.start_byte, e.end_byte} }
      start_byte = sorted.first.start_byte
      old_end    = sorted.max_of { |e| e.end_byte }
      new_end    = old_end + sorted.sum(0) { |e| e.replacement.bytesize - (e.end_byte - e.start_byte) }
      LibTreeSitter::InputEdit.new(
        start_byte: start_byte.to_u32,
        old_end_byte: old_end.to_u32,
        new_end_byte: new_end.to_u32,
        start_point: point_at(source.to_slice, start_byte),
        old_end_point: point_at(source.to_slice, old_end),
        new_end_point: point_at(result.to_slice, new_end)
      )
    end

    private def point_at(bytes : Bytes, byte : Int) : LibTreeSitter::Point
      row        = 0_u32
      line_start = 0
      i          = 0
      while i < byte
        if bytes[i] == 0x0A
          row += 1
          line_start = i + 1
        end
        i += 1
      end
      LibTreeSitter::Point.new(row: row, column: (byte - line_start).to_u32)
    end
  end
end
