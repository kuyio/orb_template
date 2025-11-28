# frozen_string_literal: true

module ORB
  module AST
    class AbstractNode
      attr_accessor :children, :attributes, :errors

      def initialize(*_args)
        @children = []
        @errors = []
      end

      def add_child(node)
        @children << node
      end

      def render(_context)
        raise "Not implemented - you must implement render in your subclass!"
      end

      def ==(other)
        self.class == other.class &&
          @children == other.children
      end
    end
  end
end
