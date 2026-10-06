# src/ts-edit/diff.cr
module TsEdit::Diff
  extend self

  alias Op = Tuple(Symbol, String, Int32, Int32)

  def unified(old : String, new : String, context : Int32 = 3) : String
    old_lines = lines_of(old)
    new_lines = lines_of(new)
    return "" if old_lines == new_lines

    io = IO::Memory.new
    build_hunks(diff_ops(old_lines, new_lines), context).each_with_index do |hunk, i|
      io << '\n' if i > 0
      old_count = hunk.count { |op| op[0] != :add }
      new_count = hunk.count { |op| op[0] != :del }
      old_start = start_line(hunk, :add, old_count)
      new_start = start_line(hunk, :del, new_count)
      io << "@@ -" << old_start << ',' << old_count << " +" << new_start << ',' << new_count << " @@\n"
      hunk.each do |tag, line, _, _|
        case tag
        when :eq  then io << ' ' << line << '\n'
        when :del then io << '-' << line << '\n'
        when :add then io << '+' << line << '\n'
        end
      end
    end
    io.to_s
  end

  private def lines_of(text : String) : Array(String)
    text.each_line.map(&.chomp).to_a
  end

  private def start_line(hunk : Array(Op), skip_tag : Symbol, count : Int32) : Int32
    ref = hunk.find { |op| op[0] != skip_tag } || hunk.first
    no  = skip_tag == :add ? ref[2] : ref[3]
    count == 0 ? no - 1 : no
  end

  private def diff_ops(old_lines : Array(String), new_lines : Array(String)) : Array(Op)
    n   = old_lines.size
    m   = new_lines.size
    lcs = Array(Array(Int32)).new(n + 1) { Array(Int32).new(m + 1, 0) }
    n.downto(1) do |i|
      m.downto(1) do |j|
        lcs[i - 1][j - 1] = old_lines[i - 1] == new_lines[j - 1] ? lcs[i][j] + 1 : {lcs[i][j - 1], lcs[i - 1][j]}.max
      end
    end

    ops = [] of Op
    i   = j = 0
    old_no = new_no = 1
    while i < n && j < m
      if old_lines[i] == new_lines[j]
        ops << {:eq, old_lines[i], old_no, new_no}
        i += 1; j += 1; old_no += 1; new_no += 1
      elsif lcs[i + 1][j] >= lcs[i][j + 1]
        ops << {:del, old_lines[i], old_no, new_no}
        i += 1; old_no += 1
      else
        ops << {:add, new_lines[j], old_no, new_no}
        j += 1; new_no += 1
      end
    end
    while i < n
      ops << {:del, old_lines[i], old_no, new_no}
      i += 1; old_no += 1
    end
    while j < m
      ops << {:add, new_lines[j], old_no, new_no}
      j += 1; new_no += 1
    end
    ops
  end

  private def build_hunks(ops : Array(Op), context : Int32) : Array(Array(Op))
    changed = [] of Int32
    ops.each_with_index { |op, i| changed << i unless op[0] == :eq }
    return [] of Array(Op) if changed.empty?

    ranges = [] of Tuple(Int32, Int32)
    lo     = {changed.first - context, 0}.max
    hi     = {changed.first + context, ops.size - 1}.min
    changed[1..].each do |idx|
      next_lo = {idx - context, 0}.max
      next_hi = {idx + context, ops.size - 1}.min
      if next_lo <= hi + 1
        hi = next_hi
      else
        ranges << {lo, hi}
        lo = next_lo
        hi = next_hi
      end
    end
    ranges << {lo, hi}

    ranges.map { |(r_lo, r_hi)| ops[r_lo..r_hi] }
  end
end
