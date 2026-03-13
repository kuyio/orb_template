# frozen_string_literal: true

module ORB
  module AST
    class AbstractNode
      attr_accessor :children, :attributes
      attr_writer :errors

      EMPTY_ARRAY = [].freeze

      def initialize(*_args)
        @children = []
      end

      def errors
        @errors || EMPTY_ARRAY
      end

      def add_child(node)
        @children << node
      end

      def add_error(error)
        (@errors ||= []) << error
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
