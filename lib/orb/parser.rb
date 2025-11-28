# frozen_string_literal: true

require 'strscan'

module ORB
  # The `Parser` is responsible for converting a list of tokens produced
  # by the `Lexer` into an Abstract Syntax Tree (AST). Any errors encountered
  # during parsing are stored in `@errors` and can be accessed after parsing.
  class Parser
    attr_reader :tokens, :errors

    class << self
      def parse(tokens, options = {})
        new(tokens, options).parse
      end
    end

    # Create a new parser instance, use `Parser.parse` instead.
    def initialize(tokens, options = {})
      @tokens = tokens
      @options = options
      @errors = []

      @root = ORB::AST::RootNode.new
      @nodes = [@root]
    end

    # Parse the tokens into a tree of nodes. The `@current` index is used to
    # keep track of the current token being parsed within the stream of tokens.
    def parse
      return @root if @tokens.empty?

      @current = 0
      next_token while @current < @tokens.length

      # If there are any nodes left in the stack, they are unmatched tokens
      raise ORB::ParserError, "Unmatched #{@nodes.last.class}" if @nodes.length > 1

      # Return the root node
      @root
    end

    alias_method :parse!, :parse

    private

    def next_token
      token = @tokens[@current]

      case token.type
      when :public_comment
        parse_public_comment(token)
      when :private_comment
        parse_private_comment(token)
      when :text
        parse_text(token)
      when :printing_expression
        parse_printing_expression(token)
      when :control_expression
        parse_control_expression(token)
      when :block_open
        parse_block_open(token)
      when :block_close
        parse_block_close(token)
      when :tag_open
        parse_tag(token)
      when :tag_close
        parse_tag_close(token)
      when :newline
        parse_newline(token)
      else
        raise ORB::ParserError, "Unknown token type: #{token.inspect}"
      end
    end

    def parse_public_comment(token)
      node = ORB::AST::PublicCommentNode.new(token)
      current_node.children << node

      @current += 1
    end

    def parse_private_comment(token)
      node = ORB::AST::PrivateCommentNode.new(token)
      current_node.children << node

      @current += 1
    end

    def parse_text(token)
      node = ORB::AST::TextNode.new(token)
      current_node.children << node

      @current += 1
    end

    def parse_tag(token)
      node = ORB::AST::TagNode.new(token)

      if node.self_closing?
        current_node.children << node
      else
        @nodes << node
      end

      @current += 1
    end

    def parse_tag_close(token)
      node = @nodes.pop
      raise(ORB::ParserError, "Unmatched closing tag '#{token.value}'") unless node.is_a?(ORB::AST::TagNode)

      current_node.children << node

      @current += 1
    end

    def parse_printing_expression(token)
      node = ORB::AST::PrintingExpressionNode.new(token)

      if node.block?
        @nodes << node
      elsif node.end?
        node = @nodes.pop
        current_node.children << node
      else
        current_node.children << node
      end

      @current += 1
    end

    def parse_control_expression(token)
      node = ORB::AST::ControlExpressionNode.new(token)

      if node.block?
        @nodes << node
      elsif node.end?
        node = @nodes.pop
        current_node.children << node
      else
        current_node.children << node
      end

      @current += 1
    end

    def parse_block_open(token)
      node = ORB::AST::BlockNode.new(token)
      @nodes << node

      @current += 1
    end

    def parse_block_close(token)
      node = @nodes.pop
      raise(ORB::ParserError, "Unmatched closing block '#{token.value}'") unless node.is_a?(ORB::AST::BlockNode)

      current_node.children << node

      @current += 1
    end

    def parse_newline(token)
      node = ORB::AST::NewlineNode.new(token)
      current_node.children << node

      @current += 1
    end

    # Helpers

    def current_node
      @nodes.last
    end

    # Helper for raising exceptions during parsing
    def parser_error!(message)
      raise ORB::ParserError.new(message, @tokens[@current].line)
    end
  end
end
