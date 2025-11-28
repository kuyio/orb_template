# frozen_string_literal: true

module ORB
  module AST
    extend ActiveSupport::Autoload

    autoload :AbstractNode
    autoload :RootNode
    autoload :PublicCommentNode
    autoload :PrivateCommentNode
    autoload :TextNode
    autoload :TagNode
    autoload :Attribute
    autoload :PrintingExpressionNode
    autoload :ControlExpressionNode
    autoload :BlockNode
    autoload :NewlineNode
  end
end
