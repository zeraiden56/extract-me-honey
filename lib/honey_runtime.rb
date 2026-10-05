# frozen_string_literal: true

# Keep platform differences here so desktop and browser use the same game.
module HoneyRuntime
  ParseError = Ruby2D.web? ? Ruby2D::JsonParser::ParseError : JSON::ParserError

  def self.monotonic_time
    Ruby2D.web? ? Ruby2D::DSL.window.elapsed : Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def self.parse_save(text)
    Ruby2D.web? ? Ruby2D::JsonParser.parse(text) : JSON.parse(text)
  end

  # Our sanitized save contains only hashes with known ASCII keys and numbers.
  # mruby has no JSON gem; the reader is already bundled with Ruby2D.
  def self.encode_save(value)
    if value.is_a?(Hash)
      '{' + value.map { |key, entry| "\"#{key}\":#{encode_save(entry)}" }.join(',') + '}'
    elsif value.is_a?(Integer) || (value.is_a?(Float) && value.finite?)
      value.to_s
    else
      raise ArgumentError, 'Save contains an unsupported value'
    end
  end

  def self.write_save(path, state)
    if Ruby2D.web?
      text = encode_save(state)
      File.open(path, 'w') { |file| file.write(text) }
      # The web shell stores this in localStorage synchronously. Never sent out.
      puts "__HONEY_SAVE__#{text}"
    else
      FileUtils.mkdir_p(File.dirname(path))
      temp = "#{path}.tmp.#{$$}"
      begin
        File.write(temp, JSON.pretty_generate(state))
        File.rename(temp, path)
      ensure
        File.delete(temp) if File.file?(temp)
      end
    end
  end
end
