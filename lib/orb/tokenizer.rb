# frozen_string_literal: true

require 'stringio'

module ORB
  class Tokenizer
    attr_reader :tokens, :errors

    SPACE_CHARS                   = [" ", "\s", "\t", "\r", "\n", "\f"].freeze
    NAME_STOP_CHARS               = SPACE_CHARS + [">", "/", "="]
    UNQUOTED_VALUE_INVALID_CHARS  = ['"', "'", "=", "<", "`"].freeze
    UNQUOTED_VALUE_STOP_CHARS     = SPACE_CHARS + [">"]
    BLOCK_NAME_STOP_CHARS         = SPACE_CHARS + ["}"]
    START_TAG_START               = "<"
    START_TAG_END                 = ">"
    START_TAG_END_SELF_CLOSING    = "/>"
    END_TAG_START                 = "</"
    END_TAG_END                   = ">"
    COMMENT_START                 = "<!--"
    COMMENT_END                   = "-->"
    PCOMMENT_START                = "{!--"
    PCOMMENT_END                  = "--}"
    PEXPRESSION_START             = "{{"
    PEXPRESSION_END               = "}}"
    NPEXPRESSION_START            = "{%"
    NPEXPRESSION_END              = "%}"
    START_BLOCK_START             = "{#"
    START_BLOCK_END               = "}"
    END_BLOCK_START               = "{/"
    END_BLOCK_END                 = "}"
    ERB_START                     = "<%"
    ERB_END                       = "%>"
    ATTRIBUTE_ASSIGN              = "="
    SINGLE_QUOTE                  = "'"
    DOUBLE_QUOTE                  = '"'
    BRACE_OPEN                    = "{"
    BRACE_CLOSE                   = "}"
    CR                            = "\r"
    NL                            = "\n"
    CRLF                          = "\r\n"

    IGNORED_BODY_TAGS = %w[script style].freeze
    VOID_ELEMENTS     = %w[area base br col command embed hr img input keygen link meta param source track wbr].freeze

    # For error messages
    HUMAN_READABLE_STATE_NAMES = {
      initial: "Input",
      comment: "Comment",
      pcomment: "ORB Comment",
      tag_open: "Tag",
      tag_close: "Closing Tag",
      tag_name: "Tag Name",
      maybe_tag_open_end: "Tag",
      maybe_tag_close_end: "Closing Tag",
      tag_attribute: "Attribute",
      attribute_maybe_value: "Attribute Value",
      attribute_value_begin: "Attribute Value",
      attribute_value_double_quote: "Attribute Value",
      attribute_value_single_quote: "Attribute Value",
      attribute_value_expression: "Attribute Value",
      block_open: "Block",
      maybe_block_end: "Block",
      block_close: "Block",
      pexpression: "Expression",
      npexpression: "Expression",
      erb_expression: "Expression",
    }.freeze

    def initialize(source, opts = {})
      @source = source
      @tokens = []
      @errors = []

      # Options
      @file = opts.fetch(:file, :nofile)
      @line = opts.fetch(:line, 1)
      @column = opts.fetch(:column, 1)
      @indentation = opts.fetch(:indentation, 0)
      @raise_errors = opts.fetch(:raise_errors, false)

      # State
      @cursor = 0
      @buffer = StringIO.new
      @current_line = @line
      @current_column = @column
      @column_offset = @indentation + 1
      @embedded_expression = false
      clear_braces
      clear_attributes
      transition_to(:initial)
    end

    # Main entry point, and only public method. Tokenize the source string and return the tokens.
    # If any errors are encountered during tokenization, this method will raise the first error.
    def tokenize!
      next_token while @cursor < @source.length

      # Write out any remaining text in the buffer
      text = consume_buffer
      @tokens << Token.new(:text, text) unless text.strip.empty?

      # Run checks to ensure the tokenizer state is valid, report any errors
      check_tokenizer_state
      check_for_unclosed_blocks_or_tags

      @tokens
    end

    alias_method :tokenize, :tokenize!

    private

    # -------------------------------------------------------------------------
    # Dispatch
    # -------------------------------------------------------------------------

    # Transitions to the appropriate tokenization method based on the current state
    # or terminates the tokenizer if an invalid state is reached.
    #
    # rubocop:disable Metrics/CyclomaticComplexity
    def next_token
      debug "STATE: #{@state}"

      case @state
      when :initial
        tokenize_text
      when :public_comment
        tokenize_comment
      when :pcomment
        tokenize_pcomment
      when :tag_open
        tokenize_tag_open
      when :tag_close
        tokenize_tag_close
      when :tag_name
        tokenize_tag_name
      when :maybe_tag_open_end
        tokenize_maybe_tag_open_end
      when :maybe_tag_close_end
        tokenize_maybe_tag_close_end
      when :tag_attribute
        tokenize_tag_attribute
      when :attribute_maybe_value
        tokenize_attribute_maybe_value
      when :attribute_value_begin
        tokenize_attribute_value_begin
      when :attribute_value_double_quote
        tokenize_attribute_value_double_quote
      when :attribute_value_single_quote
        tokenize_attribute_value_single_quote
      when :attribute_value_expression
        tokenize_attribute_value_expression
      when :block_open
        tokenize_block_open
      when :maybe_block_end
        tokenize_maybe_block_end
      when :block_close
        tokenize_block_close
      when :pexpression
        tokenize_pexpression
      when :npexpression
        tokenize_npexpression
      when :erb
        tokenize_erb
      else
        terminate
      end
    end
    # rubocop:enable Metrics/CyclomaticComplexity

    # -------------------------------------------------------------------------
    # Initial State
    # -------------------------------------------------------------------------

    # This is the main state transition method, invoked when the tokenizer is in the :initial state.
    # In this state, we either transition to a specific token state based on the text lookahead,
    # or we consume the next character (appending it to the buffer), and stay in the :initial state.
    def tokenize_text
      text = @source[@cursor..]

      if text.start_with?(CRLF)
        consume(CRLF, newline: true)
      elsif text.start_with?(NL)
        consume(NL, newline: true)
      elsif text.start_with?(COMMENT_START)
        consume(COMMENT_START, skip: true)
        add_text_node_from_buffer_and_clear
        transition_to(:public_comment)
      elsif text.start_with?(PCOMMENT_START)
        consume(PCOMMENT_START, skip: true)
        add_text_node_from_buffer_and_clear
        transition_to(:pcomment)
      elsif text.start_with?(END_TAG_START)
        consume(END_TAG_START, skip: true)
        add_text_node_from_buffer_and_clear
        transition_to(:tag_close)
      elsif text.start_with?(START_TAG_START)
        consume(START_TAG_START, skip: true)
        add_text_node_from_buffer_and_clear
        transition_to(:tag_open)
      elsif text.start_with?(START_BLOCK_START)
        consume(START_BLOCK_START, skip: true)
        add_text_node_from_buffer_and_clear
        transition_to(:block_open)
      elsif text.start_with?(END_BLOCK_START)
        consume(END_BLOCK_START, skip: true)
        add_text_node_from_buffer_and_clear
        transition_to(:block_close)
      elsif text.start_with?(PEXPRESSION_START)
        consume(PEXPRESSION_START, skip: true)
        add_text_node_from_buffer_and_clear
        transition_to(:pexpression)
      elsif text.start_with?(NPEXPRESSION_START)
        consume(NPEXPRESSION_START, skip: true)
        add_text_node_from_buffer_and_clear
        transition_to(:npexpression)
      else
        consume(text[0])
      end
    end

    # -------------------------------------------------------------------------
    # Comments
    # -------------------------------------------------------------------------

    # Public (regular HTML) comment
    # In this state, we consume characters until the look-ahead sees the next COMMENT_END (`-->`).
    # Whitespace characters are included in the comment.
    def tokenize_comment
      text = @source[@cursor..]
      syntax_error!("Expected closing '-->'") if text.empty?

      if text.start_with?(CRLF)
        consume(CRLF, newline: true)
      elsif text.start_with?(NL)
        consume(NL, newline: true)
      elsif text.start_with?(COMMENT_END)
        consume(COMMENT_END, skip: true)
        content = consume_buffer
        @tokens << Token.new(:public_comment, content)
        transition_to(:initial)
      else
        consume(text[0])
      end
    end

    # Private (ORB) comment
    # In this state, we consume characters until the look-ahead sees the next PCOMMENT_END (`--}`).
    # Whitespace characters are included in the comment.
    def tokenize_pcomment
      text = @source[@cursor..]
      syntax_error!("Expected closing '--}'") if text.empty?

      if text.start_with?(CRLF)
        consume(CRLF, newline: true)
      elsif text.start_with?(NL)
        consume(NL, newline: true)
      elsif text.start_with?(PCOMMENT_END)
        consume(PCOMMENT_END, skip: true)
        content = consume_buffer
        @tokens << Token.new(:private_comment, content)
        transition_to(:initial)
      else
        consume(text[0])
      end
    end

    # -------------------------------------------------------------------------
    # Tags
    # -------------------------------------------------------------------------

    # The tokenizer look-ahead saw a START_TAG_START, landing us in this state.
    def tokenize_tag_open
      # Read the tag name from the input.
      name = tokenize_tag_name

      # Push a new :tag_open token on the @tokens stack
      @tokens << Token.new(:tag_open, name)

      # Advance the state to :maybe_tag_open_end
      transition_to(:maybe_tag_open_end)
    end

    # The tokenizer look-ahead saw a END_TAG_START, landing us in this state.
    def tokenize_tag_close
      # Read the tag name from the input.
      name = tokenize_tag_name

      # Push a new :tag_close token on the @tokens stack
      @tokens << Token.new(:tag_close, name)

      # Advance the state to :maybe_tag_close_end
      transition_to(:maybe_tag_close_end)
    end

    # Recurses to read the tag name from the source, character by character.
    def tokenize_tag_name
      text = @source[@cursor..]
      syntax_error("Unexpected end of input: expected a tag name instead") if text.empty?

      # We are finished reading the tag name, if we encounter a NAME_STOP_CHAR
      # otherwise, we continue to consume characters and recurse.
      if NAME_STOP_CHARS.include?(text[0])
        consume_buffer

      else
        consume(text[0])
        tokenize_tag_name
      end
    end

    # In this state, we are tokenizing the tag definition until we reach the end of the tag.
    # If the tag is self-closing, it will end with `/>`. Otherwise, it will end with `>`.
    # While in this tokenization state, we skip any whitespace characters.
    # Any character we encounter that is neither whitespace nor the end of the tag is considered
    # an attribute and transitions the tokenizer to the `tag_attribute` state.
    def tokenize_maybe_tag_open_end
      text = @source[@cursor..]
      syntax_error!("Unexpected end of input: did you miss a '>' or '/>'?") if text.empty?

      if text.start_with?(CRLF)
        consume(CRLF, newline: true, skip: true)
      elsif text.start_with?(NL)
        consume(NL, newline: true, skip: true)
      elsif SPACE_CHARS.include?(text[0])
        consume(text[0], skip: true)
      elsif text.start_with?(START_TAG_END_SELF_CLOSING)
        consume(START_TAG_END_SELF_CLOSING, skip: true)
        current_token.set_meta(:self_closing, true)
        current_token.set_meta(:attributes, @attributes)
        clear_attributes
        transition_to(:initial)
      elsif text.start_with?(START_TAG_END)
        consume(START_TAG_END, skip: true)
        current_token.set_meta(:self_closing, VOID_ELEMENTS.include?(current_token.value))
        current_token.set_meta(:attributes, @attributes)
        clear_attributes
        transition_to(:initial)
      elsif text.start_with?(START_TAG_START)
        syntax_error!("Unexpected start of new tag: did you miss a '>' or '/>'?")
      else
        transition_to(:tag_attribute)
      end
    end

    # In this state, we're looking for the end of the closing tag, which must be `>`.
    # If the next character is `>`, we transition to the `initial` state.
    # Otherwise, we raise a parse error.
    def tokenize_maybe_tag_close_end
      text = @source[@cursor..]
      if text.start_with?(END_TAG_END)
        consume(END_TAG_END, skip: true)
        transition_to(:initial)
      else
        syntax_error!("Syntax error: you must close a tag with '>'")
      end
    end

    # -------------------------------------------------------------------------
    # Tag Attributes
    # -------------------------------------------------------------------------

    # In this state, we begin the process of tokenizing an attribute.
    # We start by reading the attribute name and assuming a value of 'true',
    # which is the default for HTML5 attributes without an assigned value.
    # After reading the attribute name, the tokenizer transitions to the
    # `attribute_maybe_value` state.
    def tokenize_tag_attribute
      name = tokenize_tag_name
      @attributes << [name, :bool, true]

      transition_to(:attribute_maybe_value)
    end

    # In this state, we attempt to determine whether an attribute value is present.
    # If an attribute value is present, the next character will be `=`. If it is not,
    # we transition to the `maybe_tag_open_end` state.
    # In case an attribute value is present, we transition to the `attribute_value_begin` state.
    # As usual, we skip over any whitespace characters.
    def tokenize_attribute_maybe_value
      text = @source[@cursor..]
      if text.start_with?(CRLF)
        consume(CRLF, newline: true, skip: true)
      elsif text.start_with?(NL)
        consume(NL, newline: true, skip: true)
      elsif SPACE_CHARS.include?(text[0])
        consume(text[0], skip: true)
      elsif text.start_with?(ATTRIBUTE_ASSIGN)
        consume(ATTRIBUTE_ASSIGN, skip: true)
        transition_to(:attribute_value_begin)
      else
        transition_to(:maybe_tag_open_end)
      end
    end

    # Attribute Values

    # In this state, we begin the process of tokenizing an attribute value, skipping any whitespace.
    # The first character of the attribute value will determine the type of value we're dealing with.
    # - if the first character is a double quote, we transition to the `attribute_value_double_quote` state.
    # - if the first character is a single quote, we transition to the `attribute_value_single_quote` state.
    # - if the first character is a `{`, we transition to the `attribute_value_expression` state.
    #
    # TODO: we do not support unquoted attribute values at the moment.
    def tokenize_attribute_value_begin
      text = @source[@cursor..]
      if text.start_with?(CRLF)
        consume(CRLF, newline: true, skip: true)
      elsif text.start_with?(NL)
        consume(NL, newline: true, skip: true)
      elsif SPACE_CHARS.include?(text[0])
        consume(text[0], skip: true)
      elsif text.start_with?(DOUBLE_QUOTE)
        consume(DOUBLE_QUOTE, skip: true)
        transition_to(:attribute_value_double_quote)
      elsif text.start_with?(SINGLE_QUOTE)
        consume(SINGLE_QUOTE, skip: true)
        transition_to(:attribute_value_single_quote)
      elsif text.start_with?(BRACE_OPEN)
        consume(BRACE_OPEN, skip: true)
        expr = tokenize_attribute_value_expression
        current_attribute[1] = :expr
        current_attribute[2] = expr
        transition_to(:maybe_tag_open_end)
      else
        syntax_error!("Unexpected character '#{text[0]}' in attribute value definition.")
      end
    end

    # The attribute value is a dynamic expression, which is enclosed in `{}`.
    # During this state, we consume characters until we reach the closing `}`.
    # We keep track of the number of opening and closing braces on the @braces stack
    # to ensure we have a balanced expression and don't exit too early.
    def tokenize_attribute_value_expression
      text = @source[@cursor..]
      syntax_error!("Unexpected end of input: expected closing `}`") if text.empty?

      if text.start_with?(CRLF)
        consume(CRLF, newline: true)
        tokenize_attribute_value_expression
      elsif text.start_with?(NL)
        consume(NL, newline: true)
        tokenize_attribute_value_expression
      elsif text.start_with?(BRACE_CLOSE) && @braces.empty?
        consume(BRACE_CLOSE, skip: true)
        expr = consume_buffer
        clear_braces
        expr
      elsif text.start_with?(BRACE_CLOSE)
        consume(BRACE_CLOSE)
        @braces.pop
        tokenize_attribute_value_expression
      elsif text.start_with?(BRACE_OPEN)
        consume(BRACE_OPEN)
        @braces << BRACE_OPEN
        tokenize_attribute_value_expression
      else
        consume(text[0])
        tokenize_attribute_value_expression
      end
    end

    # The attribute value is enclosed in double quotes ("").
    # If we encounter double curly braces `{{`, we set the `@embedded_expression` flag to true
    # While this flag is set, we consume double quotes as regular characters.
    # Encountering a closing double curly brace `}}` will clear the flag, and the next double quote
    # will be treated as the end of the attribute value.
    #
    # TODO: currently, we ignore the embedded expression and treat it as a regular string.
    # TODO: how should we handle escaped double quotes?
    def tokenize_attribute_value_double_quote
      text = @source[@cursor..]
      syntax_error!("Unexpected end of input: expected closing `\"`") if text.empty?

      if text.start_with?(CRLF)
        consume(CRLF, newline: true, skip: true)
      elsif text.start_with?(NL)
        consume(NL, newline: true, skip: true)
      elsif text.start_with?(PEXPRESSION_START)
        consume(PEXPRESSION_START)
        @embedded_expression = true
      elsif text.start_with?(PEXPRESSION_END)
        consume(PEXPRESSION_END)
        @embedded_expression = false
      elsif text.start_with?(DOUBLE_QUOTE) && @embedded_expression
        consume(DOUBLE_QUOTE)
      elsif text.start_with?(DOUBLE_QUOTE)
        consume(DOUBLE_QUOTE, skip: true)
        value = consume_buffer
        current_attribute[1] = :str
        current_attribute[2] = value
        transition_to(:maybe_tag_open_end)
      else
        consume(text[0])
      end
    end

    # The attribute value is enclosed in single quotes ('').
    # If we encounter double curly braces `{{`, we set the `@embedded_expression` flag to true
    # While this flag is set, we consume single quotes as regular characters.
    # Encountering a closing double curly brace `}}` will clear the flag, and the next single quote
    # will be treated as the end of the attribute value.
    #
    # TODO: currently, we ignore the embedded expression and treat it as a regular string.
    # TODO: how should we handle escaped single quotes?
    def tokenize_attribute_value_single_quote
      text = @source[@cursor..]
      syntax_error!("Parse error: expected closing `'`") if text.empty?

      if text.start_with?(CRLF)
        consume(CRLF, newline: true, skip: true)
      elsif text.start_with?(NL)
        consume(NL, newline: true, skip: true)
      elsif text.start_with?(PEXPRESSION_START)
        consume(PEXPRESSION_START)
        @embedded_expression = true
      elsif text.start_with?(PEXPRESSION_END)
        consume(PEXPRESSION_END)
        @embedded_expression = false
      elsif text.start_with?(SINGLE_QUOTE) && @embedded_expression
        consume(SINGLE_QUOTE)
      elsif text.start_with?(SINGLE_QUOTE)
        consume(SINGLE_QUOTE, skip: true)
        value = consume_buffer
        current_attribute[1] = :str
        current_attribute[2] = value
        transition_to(:maybe_tag_open_end)
      else
        consume(text[0])
      end
    end

    # -------------------------------------------------------------------------
    # Expressions
    # -------------------------------------------------------------------------

    # The lookahead in :initial state saw an opening double curly brace `{{`, landing us in this state.
    # We consume characters until we reach the closing double curly brace `}}`.
    # During this state, we keep track of the number of opening and closing braces on the @braces stack
    # to ensure we have a balanced expression and don't exit too early.
    def tokenize_pexpression
      text = @source[@cursor..]
      if text.start_with?(CRLF)
        consume(CRLF, newline: true)
      elsif text.start_with?(NL)
        consume(NL, newline: true)
      elsif text.start_with?(PEXPRESSION_END) && @braces.empty?
        consume(PEXPRESSION_END, skip: true)
        value = consume_buffer.strip
        @tokens << Token.new(:printing_expression, value)
        transition_to(:initial)
      elsif text.start_with?(BRACE_CLOSE)
        consume(BRACE_CLOSE)
        @braces.pop
      elsif text.start_with?(BRACE_OPEN)
        consume(BRACE_OPEN)
        @braces << BRACE_OPEN
      else
        consume(text[0])
      end
    end

    # The lookahead in :initial state saw an opening curly brace and an percent `{%`, landing us in this state.
    # We consume characters until we reach the closing percent and curly brace `%}`.
    # During this state, we keep track of the number of opening and closing braces on the @braces stack
    # to ensure we have a balanced expression and don't exit too early.
    def tokenize_npexpression
      text = @source[@cursor..]
      if text.start_with?(CRLF)
        consume(CRLF, newline: true)
      elsif text.start_with?(NL)
        consume(NL, newline: true)
      elsif text.start_with?(NPEXPRESSION_END) && @braces.empty?
        consume(NPEXPRESSION_END, skip: true)
        value = consume_buffer.strip
        @tokens << Token.new(:control_expression, value)
        transition_to(:initial)
      elsif text.start_with?(BRACE_CLOSE)
        consume(BRACE_CLOSE)
        @braces.pop
      elsif text.start_with?(BRACE_OPEN)
        consume(BRACE_OPEN)
        @braces << BRACE_OPEN
      else
        consume(text[0])
      end
    end

    # -------------------------------------------------------------------------
    # Blocks
    # -------------------------------------------------------------------------

    # The lookahead in :initial state saw a block expression `{#`, landing us in this state.
    def tokenize_block_open
      block_name = tokenize_block_name
      @tokens << Token.new(:block_open, block_name)
      transition_to(:maybe_block_end)
    end

    # In this state, we consume characters until we reach the end of the block expression.
    # we keep track of the number of opening and closing braces on the @braces stack
    # to ensure we have a balanced expression and don't exit too early.
    def tokenize_maybe_block_end
      text = @source[@cursor..]
      if text.start_with?(CRLF)
        consume(CRLF, newline: true)
      elsif text.start_with?(NL)
        consume(NL, newline: true)
      elsif text.start_with?(BRACE_CLOSE) && @braces.empty?
        consume(BRACE_CLOSE, skip: true)
        block_expr = consume_buffer.strip
        current_token.set_meta(:expression, block_expr)
        clear_braces
        transition_to(:initial)
      elsif text.start_with?(BRACE_CLOSE)
        consume(BRACE_CLOSE)
        @braces.pop
      elsif text.start_with?(BRACE_OPEN)
        consume(BRACE_OPEN)
        braces << BRACE_OPEN
      else
        consume(text[0])
      end
    end

    # The lookahead in :initial state saw a block end expression `{/`, landing us in this state.
    # We first read the ending block name, then expect to see a closing `}`. Otherwise, we raise a parse error.
    def tokenize_block_close
      block_name = tokenize_block_name

      text = @source[@cursor..]

      if text[0] == END_BLOCK_END
        consume(END_BLOCK_END, skip: true)
        @tokens << Token.new(:block_close, block_name)
        transition_to(:initial)
      else
        syntax_error!("Expected block end: did you miss a `}`?")
      end
    end

    # Recurses to read the block name from the source, character by character.
    def tokenize_block_name
      text = @source[@cursor..]
      syntax_error!("Unexpected end of input: expected a block name") if text.empty?

      # Finished reading the block name
      if BLOCK_NAME_STOP_CHARS.include?(text[0])
        consume_buffer.strip

      else
        consume(text[0])
        tokenize_block_name
      end
    end

    # -------------------------------------------------------------------------
    # Helpers
    # -------------------------------------------------------------------------

    def transition_to(state)
      @state = state
    end

    def consume(str, newline: false, skip: false)
      @buffer << str unless skip
      @cursor += str.length
      if newline
        @current_column = @column_offset
        @current_line += 1
      else
        @current_column += str.length
      end
    end

    def consume_buffer
      result = @buffer.string.clone
      @buffer = StringIO.new
      result
    end

    def add_text_node_from_buffer_and_clear(remove_whitespace = false)
      content = consume_buffer
      if remove_whitespace
        @tokens << Token.new(:text, content) unless content.strip.empty?
      else
        @tokens << Token.new(:text, content) unless content.empty?
      end
    end

    def clear_attributes
      @attributes = []
    end

    def clear_braces
      @braces = []
    end

    def terminate
      debug "TERMINATED!"
      @cursor = @source.length
    end

    def current_token
      @tokens.last
    end

    def current_attribute
      @attributes.last
    end

    def debug(msg)
      Rails.logger.debug { "[DEBUG:#{caller.length}] #{msg}" } if ENV.fetch("DEBUG", false)
    end

    def error(message)
      debug "ERROR: #{message}"
      @errors << message
      terminate
    end

    def check_tokenizer_state
      return if @state == :initial

      syntax_error!("Parse error: unexpected end of #{HUMAN_READABLE_STATE_NAMES.fetch(@state, 'input')}")
    end

    def check_for_unclosed_blocks_or_tags
      tags = []
      blocks = []

      # Walk the token stream and keep track of unclosed tags and blocks
      @tokens.each do |token|
        if token.type == :tag_open && !token.meta[:self_closing]
          tags << token
        elsif token.type == :tag_close
          tags.pop
        elsif token.type == :block_open
          blocks << token
        elsif token.type == :block_close
          blocks.pop
        end
      end

      syntax_error!("Unexpected end of input: found unclosed tags! #{tags}") unless tags.empty?

      syntax_error!("Unexpected end of input: found an unclosed ##{blocks.first.value} block.") unless blocks.empty?

      true
    end

    # Helper for raising exceptions during tokenization
    def syntax_error!(message)
      raise ORB::SyntaxError.new(message, @current_line)
    end
  end
end
