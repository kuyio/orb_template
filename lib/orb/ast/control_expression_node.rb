# frozen_string_literal: true

module ORB
  module AST
    # A node representing a non-printing expression
    # Non-printing expressions are used for control flow and variable assignment.
    # Any output from a non-printing expression is captured and discarded.
    class ControlExpressionNode < AbstractNode
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
    end
  end
end
