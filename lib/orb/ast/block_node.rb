# frozen_string_literal: true

module ORB
  module AST
    class BlockNode < AbstractNode
      def initialize(token)
        super
        @name = token.value
        @meta = token.meta
      end

      def name
        @name.to_sym
      end

      def expression
        @meta.fetch(:expression, false)
      end

      # TODO: Support render to text for different block types
      def render(_context)
        raise "BlockNode#render not implemented."
      end
    end
  end
end
