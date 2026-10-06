# src/cli.cr
require "json"
require "option_parser"
require "./ts-edit"
require "./ts-edit/dispatcher"
require "./mcp_server"

module TsEdit::CLI
  extend self

  COMMANDS      = %w[open find outline node-at edit preview expect write diff source]
  META_COMMANDS = %w[recipes languages]

  def run(argv : Array(String) = ARGV) : Int32
    command = argv[0]?
    if command == "mcp"
      McpServer.run
      return 0
    end
    unless command && (COMMANDS + META_COMMANDS).includes?(command)
      STDERR.puts "usage: ts-edit mcp | #{COMMANDS.join("|")} FILE [JSON_PARAMS] [--source] [--write] | #{META_COMMANDS.join("|")} [JSON_PARAMS]"
      return 1
    end

    show_source = false
    write_back = false
    positional = [] of String
    parser = OptionParser.new do |p|
      p.on("--source", "print the resulting source after the JSON result") { show_source = true }
      p.on("--write", "write the file in place after an edit") { write_back = true }
      p.unknown_args { |args| positional = args }
    end
    parser.parse(argv[1..])

    dispatcher = Dispatcher.new

    session_id = ""
    if COMMANDS.includes?(command)
      file = positional[0]?
      unless file
        STDERR.puts "ts-edit #{command}: missing FILE"
        return 1
      end
      opened = dispatcher.handle("open", any_params({"path" => JSON::Any.new(file)}))
      return fail(opened) if error?(opened)
      if command == "open"
        puts opened.to_json
        return 0
      end
      session_id = opened["session"].as_s
    end

    params = parse_params(positional[COMMANDS.includes?(command) ? 1 : 0]?)
    params["session"] = JSON::Any.new(session_id) unless session_id.empty?

    result = dispatcher.handle(command.tr("-", "_"), JSON::Any.new(params))
    return fail(result) if error?(result)
    puts result.to_json

    if show_source && %w[edit preview].includes?(command)
      if command == "preview"
        puts result["source"].as_s
      else
        source = dispatcher.handle("source", JSON::Any.new({"session" => JSON::Any.new(session_id)}))
        puts source["source"].as_s
      end
    end

    if write_back && command == "edit"
      written = dispatcher.handle("write", JSON::Any.new({"session" => JSON::Any.new(session_id)}))
      return fail(written) if error?(written)
    end

    0
  end

  private def parse_params(json : String?) : Hash(String, JSON::Any)
    return {} of String => JSON::Any unless json
    JSON.parse(json).as_h
  rescue ex : JSON::ParseException
    STDERR.puts %({"error":true,"type":"JSON::ParseException","message":#{ex.message.to_json}})
    exit 1
  end

  private def any_params(hash : Hash(String, JSON::Any)) : JSON::Any
    JSON::Any.new(hash)
  end

  private def error?(result : JSON::Any) : Bool
    result["error"]?.try(&.as_bool?) || false
  end

  private def fail(result : JSON::Any) : Int32
    STDERR.puts result.to_json
    1
  end
end

exit TsEdit::CLI.run
