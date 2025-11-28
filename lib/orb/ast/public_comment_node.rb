# frozen_string_literal: true

module ORB
  module AST
    class PublicCommentNode < AbstractNode
      attr_accessor :text

      def initialize(token)
        super
        @text = token.value
      end

      def render(_context)
        "<!-- #{@text} -->"
      end

      def ==(other)
        super && @text == other.text
      end
    end
  end
end
