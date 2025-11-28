# frozen_string_literal: true

module ORB
  module AST
    class RootNode < AbstractNode
      def render(context = {})
        @children.map { |child| child.render(context) }.join
      end
    end
  end
end
