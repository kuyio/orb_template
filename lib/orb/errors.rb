# frozen_string_literal: true

module ORB
  class Error < StandardError
    attr_reader :line

    def initialize(message = nil, line = nil)
      super(message)
      @line = line
    end
  end

  # class SyntaxError < StandardError
  #   attr_reader :error, :file, :line, :lineno, :column

  #   def initialize(error, file, line, lineno, column)
  #     @error = error
  #     @file = file || '(__TEMPLATE__)'
  #     @line = line.to_s
  #     @lineno = lineno
  #     @column = column
  #   end

  #   def to_s
  #     line = @line.lstrip
  #     column = @column + line.size - @line.size
  #     message = <<~STR
  #       #{error}
  #       in #{file}, Line #{lineno}, Column #{@column}

  #       #{line}
  #       #{' ' * column}^
  #     STR
  #   end
  # end

  class SyntaxError < Error; end
  class ParserError < Error; end
  class CompilerError < Error; end
end
