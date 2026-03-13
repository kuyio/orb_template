# frozen_string_literal: true

module ORB
  module AST
    # A node representing a printing expression
    class PrintingExpressionNode < AbstractNode
      BLOCK_RE = /\A(if|unless)\b|\bdo\s*(\|[^|]*\|)?\s*$/

      attr_reader :expression

      def initialize(token)
        super
        @expression = token.value
        @is_block = BLOCK_RE.match?(@expression)
        @is_end = @expression == 'end' || @expression.strip == 'end'
      end

      def block?
        @is_block
      end

      def end?
        @is_end
      end

      def render(_context)
        "NOT IMPLEMENTED"
      end
    end
  end
end
