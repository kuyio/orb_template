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
      end

      def block?
        @expression =~ BLOCK_RE
      end

      def end?
        @expression.strip == 'end'
      end

      def render(_context)
        "NOT IMPLEMENTED"
      end
    end
  end
end
