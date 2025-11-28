# frozen_string_literal: true

require 'strscan'
require_relative 'patterns'

module ORB
  # Tokenizer2 is a streaming, non-recursive tokenizer for ORB templates.
  #
  # It scans the source sequentially and emits tokens as it passes over the input.
  # During scanning, it keeps track of the current state and the list of tokens.
  # Any consumption of the source, either by buffering or skipping moves the cursor.
  # The cursor position is used to keep track of the current line and column in the
  # virtual source document. When tokens are generated, they are annotated with the
  # position they were found in the virtual document.
  class Tokenizer2
    include ORB::Patterns

    # Tags that should be ignored
    IGNORED_BODY_TAGS = %w[script style].freeze

    # Tags that are self-closing by HTML5 spec
    VOID_ELEMENTS     = %w[area base br col command embed hr img input keygen link meta param source track wbr].freeze

    attr_reader :errors, :tokens

    def initialize(source, options = {})
      @source = StringScanner.new(source)
      @raise_errors = options.fetch(:raise_errors, true)

      # Streaming Tokenizer State
      @cursor = 0
      @column = 1
      @line = 1
      @errors = []
      @tokens = []
      @attributes = []
      @braces = []
      @state = :initial
      @buffer = StringIO.new
    end

    # Main Entry
    def tokenize
      next_token until @source.eos?

      # Consume remaining buffer
      buffer_to_text_token

      # Return the tokens
      @tokens
    end

    alias_method :tokenize!, :tokenize

    private

    # Dispatcher based on current state
    def next_token
      # Detect infinite loop
      # if @previous_cursor == @cursor && @previous_state == @state
      #   raise "Internal Error: detected infinite loop in :#{@state}"
      # end

      # Dispatch to state handler
      send(:"next_in_#{@state}")
    end

    # Read next token in :initial state
    # rubocop:disable Metrics/AbcSize
    def next_in_initial
      if @source.scan(NEWLINE) || @source.scan(CRLF)
        buffer_to_text_token
        add_token(:newline, @source.matched)
        move_by_matched
      elsif @source.scan(PRIVATE_COMMENT_START)
        buffer_to_text_token
        add_token(:private_comment, nil)
        move_by_matched
        transition_to(:private_comment)
      elsif @source.scan(PUBLIC_COMMENT_START)
        buffer_to_text_token
        add_token(:public_comment, nil)
        move_by_matched
        transition_to(:public_comment)
      elsif @source.scan(BLOCK_OPEN)
        buffer_to_text_token
        add_token(:block_open, nil)
        move_by_matched
        transition_to(:block_open)
      elsif @source.scan(BLOCK_CLOSE)
        buffer_to_text_token
        add_token(:block_close, nil)
        move_by_matched
        transition_to(:block_close)
      elsif @source.scan(PRINTING_EXPRESSION_START)
        buffer_to_text_token
        add_token(:printing_expression, nil)
        move_by_matched
        clear_braces
        transition_to(:printing_expression)
      elsif @source.scan(CONTROL_EXPRESSION_START)
        buffer_to_text_token
        add_token(:control_expression, nil)
        move_by_matched
        clear_braces
        transition_to(:control_expression)
      elsif @source.scan(END_TAG_START)
        buffer_to_text_token
        add_token(:tag_close, nil)
        move_by_matched
        transition_to(:tag_close)
      elsif @source.scan(START_TAG_START)
        buffer_to_text_token
        add_token(:tag_open, nil)
        move_by_matched
        transition_to(:tag_open)
      elsif @source.scan(OTHER)
        buffer_matched
        move_by_matched
      else
        syntax_error!("Unexpected '#{@source.peek(1)}'")
      end
    end
    # rubocop:enable Metrics/AbcSize

    # Read next token in :tag_open state
    def next_in_tag_open
      if @source.scan(NEWLINE) || @source.scan(CRLF)
        move_by_matched
      elsif @source.scan(TAG_NAME)
        tag = @source.matched
        update_current_token(tag)
        move_by_matched
        clear_attributes
        transition_to(:tag_open_content)
      else
        syntax_error!("Unexpected '#{@source.peek(1)}'")
      end
    end

    # Read next token in :tag_open_content state
    def next_in_tag_open_content
      if @source.scan(NEWLINE) || @source.scan(CRLF) || @source.scan(BLANK)
        move_by_matched
      elsif @source.scan(START_TAG_END_VERBATIM)
        current_token.set_meta(:self_closing, false)
        current_token.set_meta(:verbatim, true)
        current_token.set_meta(:attributes, @attributes) if @attributes.any?
        clear_attributes
        move_by_matched
        transition_to(:verbatim)
      elsif @source.scan(START_TAG_END_SELF_CLOSING)
        current_token.set_meta(:self_closing, true)
        current_token.set_meta(:attributes, @attributes) if @attributes.any?
        clear_attributes
        move_by_matched
        transition_to(:initial)
      elsif @source.scan(START_TAG_END)
        current_token.set_meta(:self_closing, VOID_ELEMENTS.include?(current_token.value))
        current_token.set_meta(:attributes, @attributes) if @attributes.any?
        clear_attributes
        move_by_matched
        transition_to(:initial)
      elsif @source.scan(START_TAG_START)
        syntax_error!("Unexpected start of tag")
      elsif @source.scan(%r{\*[^\s>/=]+})
        splat = @source.matched
        @attributes << [nil, :splat, splat]
        move_by_matched
      elsif @source.check(OTHER)
        transition_to(:attribute_name)
      else
        syntax_error!("Unexpected '#{@source.peek(1)}'")
      end
    end

    # Read next token in :attribute_name state
    def next_in_attribute_name
      if @source.scan(ATTRIBUTE_NAME)
        @attributes << [@source.matched, :boolean, true]
        move_by_matched
        transition_to(:attribute_value?)
      else
        syntax_error!("Expected a valid attribute name")
      end
    end

    # Read next token in :attribute_value? state
    def next_in_attribute_value?
      if @source.scan(NEWLINE) || @source.scan(CRLF) || @source.scan(BLANK)
        move_by_matched
      elsif @source.scan(ATTRIBUTE_ASSIGN)
        move_by_matched
        transition_to(:attribute_value!)
      else
        transition_to(:tag_open_content)
      end
    end

    # Read next token in :attribute_value! state
    def next_in_attribute_value!
      if @source.scan(NEWLINE) || @source.scan(CRLF) || @source.scan(BLANK)
        move_by_matched
      elsif @source.scan(SINGLE_QUOTE)
        move_by_matched
        transition_to(:attribute_value_single_quoted)
      elsif @source.scan(DOUBLE_QUOTE)
        move_by_matched
        transition_to(:attribute_value_double_quoted)
      elsif @source.scan(BRACE_OPEN)
        move_by_matched
        transition_to(:attribute_value_expression)
      elsif @source.check(OTHER)
        transition_to(:attribute_value_unquoted)
      else
        syntax_error!("Unexpected '#{@source.peek(1)}'")
      end
    end

    # Read next token in :attribute_value_single_quoted state
    def next_in_attribute_value_single_quoted
      if @source.scan(SINGLE_QUOTE)
        attribute_value = consume_buffer
        current_attribute[1] = :string
        current_attribute[2] = attribute_value
        move_by_matched
        transition_to(:tag_open_content)
      elsif @source.scan(NEWLINE) || @source.scan(CRLF) || @source.scan(BLANK) || @source.scan(OTHER)
        buffer_matched
        move_by_matched
      else
        syntax_error!("Unexpected '#{@source.peek(1)}'")
      end
    end

    # Read next token in :attribute_value_double_quoted state
    def next_in_attribute_value_double_quoted
      if @source.scan(DOUBLE_QUOTE)
        attribute_value = consume_buffer
        current_attribute[1] = :string
        current_attribute[2] = attribute_value
        move_by_matched
        transition_to(:tag_open_content)
      elsif @source.scan(NEWLINE) || @source.scan(CRLF) || @source.scan(BLANK) || @source.scan(OTHER)
        buffer_matched
        move_by_matched
      else
        syntax_error!("Unexpected '#{@source.peek(1)}'")
      end
    end

    # Read next token in :attribute_value_expression state
    def next_in_attribute_value_expression
      if @source.scan(BRACE_OPEN)
        @braces << "{"
        buffer_matched
        move_by_matched
      elsif @source.scan(BRACE_CLOSE)
        if @braces.any?
          @braces.pop
          buffer_matched
          move_by_matched
        else
          attribute_expression = consume_buffer
          current_attribute[1] = :expression
          current_attribute[2] = attribute_expression.strip
          move_by_matched
          transition_to(:tag_open_content)
        end
      elsif @source.scan(NEWLINE) || @source.scan(CRLF) || @source.scan(BLANK) || @source.scan(OTHER)
        buffer_matched
        move_by_matched
      else
        syntax_error!("Unexpected end of input while reading expression attribute value")
      end
    end

    # Read next token in :attribute_value_unquoted state
    def next_in_attribute_value_unquoted
      if @source.scan(UNQUOTED_VALUE)
        attribute_value = @source.matched
        current_attribute[1] = :string
        current_attribute[2] = attribute_value
        move_by_matched
        transition_to(:tag_open_content)
      elsif @source.scan(UNQUOTED_VALUE_INVALID_CHARS)
        syntax_error!("Unexpected '#{@source.peek(1)}' in unquoted attribute value")
      else
        syntax_error!("Unexpected end of input while reading unquoted attribute value")
      end
    end

    # Read next token in :tag_close state
    def next_in_tag_close
      if @source.scan(TAG_NAME)
        buffer_matched
        move_by_matched
      elsif @source.scan(/[$?>]+/)
        tag = consume_buffer
        update_current_token(tag)
        move_by(tag)
        transition_to(:initial)
      else
        syntax_error!("Unexpected '#{@source.peek(1)}'")
      end
    end

    # Read next token in :public_comment state
    def next_in_public_comment
      if @source.scan(PUBLIC_COMMENT_END)
        text = consume_buffer
        update_current_token(text)
        move_by_matched
        transition_to(:initial)
      elsif @source.scan(NEWLINE) || @source.scan(CRLF) || @source.scan(BLANK) || @source.scan(OTHER)
        buffer_matched
        move_by_matched
      else
        syntax_error!("Unexpected input '#{@source.peek(1)}' while reading public comment")
      end
    end

    # Read tokens in :private_comment state
    def next_in_private_comment
      if @source.scan(PRIVATE_COMMENT_END)
        text = consume_buffer
        update_current_token(text)
        move_by_matched
        transition_to(:initial)
      elsif @source.scan(NEWLINE) || @source.scan(CRLF) || @source.scan(BLANK) || @source.scan(OTHER)
        buffer_matched
        move_by_matched
      else
        syntax_error!("Unexpected input '#{@source.peek(1)}' while reading public comment")
      end
    end

    # Read tokens in :block_open state
    def next_in_block_open
      if @source.scan(BLOCK_NAME_CHARS)
        block_name = @source.matched
        update_current_token(block_name)
        move_by_matched
        clear_braces
        transition_to(:block_open_content)
      else
        syntax_error!("Exptected valid block name")
      end
    end

    # Read block expression until closing brace
    def next_in_block_open_content
      if @source.scan(BRACE_OPEN)
        @braces << "{"
        buffer_matched
        move_by_matched
      elsif @source.scan(BRACE_CLOSE)
        if @braces.empty?
          block_expression = consume_buffer
          update_current_token(nil, expression: block_expression.strip)
          move_by_matched
          transition_to(:initial)
        else
          @braces.pop
          buffer_matched
          move_by_matched
        end
      elsif @source.scan(BLANK) || @source.scan(OTHER)
        buffer_matched
        move_by_matched
      end
    end

    # Read tokens in :block_close state
    def next_in_block_close
      if @source.scan(BLOCK_NAME_CHARS)
        block_name = @source.matched
        update_current_token(block_name)
        move_by_matched
        transition_to(:block_close_content)
      else
        syntax_error!("Expected valid block name")
      end
    end

    # Read block close name until closing brace
    def next_in_block_close_content
      if @source.scan(/\s/)
        move_by_matched
      elsif @source.scan(BRACE_CLOSE)
        move_by_matched
        transition_to(:initial)
      else
        syntax_error!("Expected closing brace '}'")
      end
    end

    # Read tokens in :printing_expression state
    def next_in_printing_expression
      if @source.scan(PRINTING_EXPRESSION_END)
        expression = consume_buffer
        update_current_token(expression)
        move_by_matched
        transition_to(:initial)
      elsif @source.scan(BRACE_OPEN)
        @braces << "{"
        buffer_matched
        move_by_matched
      elsif @source.scan(BRACE_CLOSE)
        if @braces.any?
          @braces.pop
          buffer_matched
          move_by_matched
        else
          syntax_error!("Unexpected closing brace '}'")
        end
      elsif @source.scan(OTHER) || @source.scan(NEWLINE) || @source.scan(CRLF)
        buffer_matched
        move_by_matched
      end
    end

    # Read tokens in :control_expression state
    def next_in_control_expression
      if @source.scan(CONTROL_EXPRESSION_END)
        expression = consume_buffer
        update_current_token(expression)
        move_by_matched
        transition_to(:initial)
      elsif @source.scan(BRACE_OPEN)
        @braces << "{"
        buffer_matched
        move_by_matched
      elsif @source.scan(BRACE_CLOSE)
        if @braces.any?
          @braces.pop
          buffer_matched
          move_by_matched
        else
          syntax_error!("Unexpected closing brace '}'")
        end
      elsif @source.scan(OTHER) || @source.scan(NEWLINE) || @source.scan(CRLF)
        buffer_matched
        move_by_matched
      end
    end

    # Read tokens in :verbatim state
    def next_in_verbatim
      if @source.scan(END_TAG_START)
        # store the match up to here in a temporary variable
        tmp = @source.matched
        # then find the next verbatim end tag end and
        # check if the tag name matches the current verbatim tag name
        lookahead = @source.check_until(END_TAG_END_VERBATIM)

        # if the tag name matches, we have found the end of the verbatim tag
        # and we can add a text token, as well as a tag_close token
        if lookahead[0..-3] == current_token.value
          buffer_to_text_token
          add_token(:tag_close, nil)
          transition_to(:tag_close)
        else
          buffer(tmp)
          move_by(tmp)
        end
      elsif @source.scan(NEWLINE) || @source.scan(CRLF) || @source.scan(BLANK) || @source.scan(OTHER)
        buffer_matched
        move_by_matched
      end
    end

    # --------------------------------------------------------------
    # Helpers

    # Terminates the tokenizer.
    def terminate
      @source.terminate
    end

    # Retrieve the current token
    def current_token
      raise "Invalid tokenizer state: no tokens present" if @tokens.empty?

      @tokens.last
    end

    def current_attribute
      raise "Invalid tokenizer state: no attributes present" if @attributes.empty?

      @attributes.last
    end

    def add_attribute(name, type, value)
      @attributes << [name, type, value]
    end

    def clear_attributes
      @attributes = []
    end

    def clear_braces
      @braces = []
    end

    # Moves the cursor
    def move(line, column)
      @line = line
      @column = column
    end

    def move_by(str)
      scan = StringScanner.new(str)
      until scan.eos?
        if scan.scan(NEWLINE) || scan.scan(CRLF)
          move(@line + 1, 1)
        elsif scan.scan(OTHER)
          move(@line, @column + scan.matched.size)
        end
      end
    end

    def move_by_matched
      move_by(@source.matched)
    end

    # Changes the state
    def transition_to(state)
      @state = state
    end

    # Create a new token
    def create_token(type, value, meta = {})
      Token.new(type, value, meta.merge(line: @line, column: @column) { |_k, v1, _v2| v1 })
    end

    # Create a token and add it to the token list
    def add_token(type, value, meta = {})
      @tokens << create_token(type, value, meta)
    end

    # Update the current token
    def update_current_token(value = nil, meta = {})
      current_token.value = value if value
      current_token.meta.merge!(meta)
    end

    # Write given str to buffer
    def buffer(str)
      @buffer << str
    end

    # Read the buffer to a string
    def read_buffer
      @buffer.string.clone
    end

    # Clear the buffer
    def clear_buffer
      @buffer = StringIO.new
    end

    # Read the buffer to a string and clear it
    def consume_buffer
      str = read_buffer
      clear_buffer
      str
    end

    def buffer_matched
      buffer(@source.matched)
    end

    # Turn the buffer into a text token
    def buffer_to_text_token
      text = consume_buffer
      add_token(:text, text, line: @line, column: @column - text.size) unless text.empty?
    end

    # Raise a syntax error
    def syntax_error!(message)
      if @raise_errors
        raise ORB::SyntaxError.new("#{message} at line #{@line} and column #{@column} during :#{@state}", @line)
      end

      @errors << ORB::SyntaxError.new("#{message} at line #{@line} and column #{@column} during :#{@state}", @line)

      terminate
    end
  end
end
