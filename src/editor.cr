# src/editor.cr
struct Edit
  getter start_byte : Int32
  getter end_byte : Int32
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
    bytes = source.to_slice
    io = IO::Memory.new(bytes.size + sorted.sum(0) { |e| e.replacement.bytesize })
    cursor = 0
    sorted.each do |edit|
      io.write bytes[cursor...edit.start_byte]
      io << edit.replacement
      cursor = edit.end_byte
    end
    io.write bytes[cursor..]
    io.to_s
  end
end
