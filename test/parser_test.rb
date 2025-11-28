# frozen_string_literal: true

require_relative "test_helper"

class ParserTest < ActiveSupport::TestCase
  # Should be able to parse an empty token list.
  # The result should be an empty AST::RootNode.
  def test_parse_empty_token_list
    tokens = []
    parser = ::ORB::Parser.new(tokens)
    result = parser.parse

    assert_equal result.class, ::ORB::AST::RootNode
    assert_empty result.children
    assert_empty parser.errors
  end

  # Should be able to parse and render a text token.
  def test_parse_and_render_text_token
    tokens = [
      ::ORB::Token.new(:text, "Hello, World!")
    ]

    parser = ::ORB::Parser.new(tokens)
    result = parser.parse

    assert_not_empty result.children
    assert_equal result.children.first, ::ORB::AST::TextNode.new(tokens.first)
    assert_equal result.children.first.render({}), "Hello, World!"
    assert_empty parser.errors
  end

  # Should be able to parse a comment token and render it.
  def test_parse_and_render_comment_token
    tokens = [
      ::ORB::Token.new(:public_comment, "Hello, World!")
    ]

    parser = ::ORB::Parser.new(tokens)
    result = parser.parse

    assert_not_empty result.children
    assert_equal result.children.first, ::ORB::AST::PublicCommentNode.new(tokens.first)
    assert_equal result.children.first.render({}), "<!-- Hello, World! -->"
    assert_empty parser.errors
  end

  # Should be able to parse a private_comment token and render it.
  def test_parse_and_render_pcomment_token
    tokens = [
      ::ORB::Token.new(:private_comment, "Hello, World!")
    ]

    parser = ::ORB::Parser.new(tokens)
    result = parser.parse

    assert_not_empty result.children
    assert_equal result.children.first, ::ORB::AST::PrivateCommentNode.new(tokens.first)
    assert_equal result.children.first.render({}), "{!-- Hello, World! --}"
    assert_empty parser.errors
  end

  # Should be able to parse an expression token and render it,
  # as long as it evaluates within the given context.
  def test_parse_token_within_valid_context
    tokens = [
      ::ORB::Token.new(:printing_expression, "name.capitalize")
    ]

    parser = ::ORB::Parser.new(tokens)
    result = parser.parse

    assert_not_empty result.children
    assert_equal result.children.first, ::ORB::AST::PrintingExpressionNode.new(tokens.first)
    assert_empty parser.errors
  end

  # Should be able to parse a block with text and an expression, as
  # long as it has a matching block_close token.
  def test_parse_block
    tokens = [
      ::ORB::Token.new(:block_open, "if", { expression: "name" }),
      ::ORB::Token.new(:text, "Hello, "),
      ::ORB::Token.new(:printing_expression, "name"),
      ::ORB::Token.new(:block_close, "if")
    ]

    parser = ::ORB::Parser.new(tokens)
    result = parser.parse
    assert_equal result.children.size, 1
    assert_equal result.children.first.class, ::ORB::AST::BlockNode
  end

  # Parsing a block_open token without a matching block_close token
  # should raise a ParserError.
  def test_parse_block_open_token_without_block_close
    tokens = [
      ::ORB::Token.new(:block_open, "if", { expression: "name" })
    ]

    parser = ::ORB::Parser.new(tokens)
    error = assert_raises(ORB::ParserError) { parser.parse }
    assert_includes error.message, "Unmatched ORB::AST::BlockNode"
  end

  # Parsing a block_close token without a matching block_open token
  # should raise a ParserError.
  def test_parse_block_close_token_without_block_open
    tokens = [
      ::ORB::Token.new(:block_close, "if")
    ]

    parser = ::ORB::Parser.new(tokens)
    error = assert_raises(ORB::ParserError) { parser.parse }
    assert_includes error.message, "Unmatched closing block 'if'"
  end

  # Should be able to parse a tag with text as long as
  # it has a matching tag_close token.
  def test_parse_tag
    tokens = [
      ::ORB::Token.new(:tag_open, "div"),
      ::ORB::Token.new(:text, "Hello, World!"),
      ::ORB::Token.new(:tag_close, "div")
    ]

    parser = ::ORB::Parser.new(tokens)
    result = parser.parse
    assert_equal result.children.size, 1
    assert_equal result.children.first.class, ::ORB::AST::TagNode
  end

  # Parsing a tag_open token without a matching tag_close token
  # should raise a ParserError.
  def test_parse_tag_open_token_without_tag_close
    tokens = [
      ::ORB::Token.new(:tag_open, "div")
    ]

    parser = ::ORB::Parser.new(tokens)
    error = assert_raises(ORB::ParserError) { parser.parse }
    assert_includes error.message, "Unmatched ORB::AST::TagNode"
  end

  # Parsing a tag_close token without a matching tag_open token
  # should raise a ParserError.
  def test_parse_tag_close_token_without_tag_open
    tokens = [
      ::ORB::Token.new(:tag_close, "div")
    ]

    parser = ::ORB::Parser.new(tokens)
    error = assert_raises(ORB::ParserError) { parser.parse }
    assert_includes error.message, "Unmatched closing tag 'div'"
  end

  # Should be able to parse a self-closing tag with attributes
  # without raising an error about an unmatched tag_close token.
  def test_parse_self_closing_tag
    tokens = [
      ::ORB::Token.new(:tag_open, "img", { self_closing: true, attributes: [["src", :str, "/public/image.jpg"]] })
    ]

    parser = ::ORB::Parser.new(tokens)
    result = parser.parse
    assert_equal result.children.size, 1
    assert_equal result.children.first.class, ::ORB::AST::TagNode
  end

  # Should be able to parse a printing expression with a block
  def test_parse_printing_expression_with_block
    tokens = [
      ::ORB::Token.new(:text, "Hello, "),
      ::ORB::Token.new(:printing_expression, "[1,2,3].each do |i|"),
      ::ORB::Token.new(:text, "Item: "),
      ::ORB::Token.new(:printing_expression, "i"),
      ::ORB::Token.new(:printing_expression, "end")
    ]
    parser = ::ORB::Parser.new(tokens)
    result = parser.parse

    assert_equal result.children.size, 2
    assert_equal result.children.first.class, ::ORB::AST::TextNode
    assert_equal result.children.last.class, ::ORB::AST::PrintingExpressionNode
    assert_equal result.children.last.expression, "[1,2,3].each do |i|"
    assert_equal result.children.last.children.size, 2
    assert_equal result.children.last.children.first.class, ::ORB::AST::TextNode
    assert_equal result.children.last.children.last.class, ::ORB::AST::PrintingExpressionNode
    assert_equal result.children.last.children.last.expression, "i"
  end

  # Should be able to parse a non-printing expression
  def test_parse_control_expression
    tokens = [
      ::ORB::Token.new(:text, "Hello, "),
      ::ORB::Token.new(:control_expression, "name = 'John'"),
      ::ORB::Token.new(:text, "!")
    ]
    parser = ::ORB::Parser.new(tokens)
    result = parser.parse

    assert_equal result.children.size, 3
    assert_equal result.children[0].class, ::ORB::AST::TextNode
    assert_equal result.children[0].text, "Hello, "

    assert_equal result.children[1].class, ::ORB::AST::ControlExpressionNode
    assert_equal result.children[1].expression, "name = 'John'"

    assert_equal result.children[2].class, ::ORB::AST::TextNode
    assert_equal result.children[2].text, "!"
  end

  # Should be able to parse a non-printing expression with a block
  def test_parse_control_expression_with_block
    tokens = [
      ::ORB::Token.new(:text, "Hello "),
      ::ORB::Token.new(:control_expression, "names = ['John', 'Smith'].each do |name|"),
      ::ORB::Token.new(:control_expression, "name + ' Miller'"),
      ::ORB::Token.new(:control_expression, "end"),
      ::ORB::Token.new(:text, "!")
    ]
    parser = ::ORB::Parser.new(tokens)
    result = parser.parse

    assert_equal result.children.size, 3
    assert_equal result.children[0].class, ::ORB::AST::TextNode
    assert_equal result.children[0].text, "Hello "
    assert_equal result.children[1].class, ::ORB::AST::ControlExpressionNode
    assert_equal result.children[1].expression, "names = ['John', 'Smith'].each do |name|"
    assert_equal result.children[1].children.size, 1
    assert_equal result.children[1].children[0].class, ::ORB::AST::ControlExpressionNode
    assert_equal result.children[1].children[0].expression, "name + ' Miller'"
    assert_equal result.children[2].class, ::ORB::AST::TextNode
    assert_equal result.children[2].text, "!"
  end

  # Should be able to close the block of a printing expression with a non-printing 'end' expression
  def test_close_pexpression_block_with_npexpression_end
    tokens = [
      ::ORB::Token.new(:printing_expression, "[1,2,3].each do |i|"),
      ::ORB::Token.new(:text, "Item: "),
      ::ORB::Token.new(:printing_expression, "i"),
      ::ORB::Token.new(:control_expression, "end")
    ]
    parser = ::ORB::Parser.new(tokens)
    result = parser.parse

    assert_equal result.children.size, 1
    assert_equal result.children.first.class, ::ORB::AST::PrintingExpressionNode
    assert_equal result.children.first.expression, "[1,2,3].each do |i|"
    assert_equal result.children.first.children.size, 2
    assert_equal result.children.first.children.first.class, ::ORB::AST::TextNode
    assert_equal result.children.first.children.last.class, ::ORB::AST::PrintingExpressionNode
    assert_equal result.children.first.children.last.expression, "i"
  end

  # Should be able to parse a tag with static attributes
  # rubocop:disable Metrics/AbcSize
  def test_parse_tag_with_static_attributes
    tokens = [
      ::ORB::Token.new(:tag_open, "div", { attributes: [["class", :str, "container"], ["id", :str, "main"]] }),
      ::ORB::Token.new(:text, "Hello, World!"),
      ::ORB::Token.new(:tag_close, "div")
    ]

    parser = ::ORB::Parser.new(tokens)
    result = parser.parse
    assert_equal result.children.size, 1
    assert_equal result.children.first.class, ::ORB::AST::TagNode
    assert_equal result.children.first.static_attributes.size, 2
    assert_equal result.children.first.dynamic_attributes.size, 0
    assert_equal result.children.first.splat_attributes.size, 0
    assert_equal result.children.first.attributes.size, 2
    assert       result.children.first.html_tag?
    assert_not   result.children.first.component_tag?
    assert_not   result.children.first.component_slot_tag?
    assert_equal result.children.first.attributes.first.class, ::ORB::AST::Attribute
    assert_equal result.children.first.attributes.first.name, "class"
    assert_equal result.children.first.attributes.first.value, "container"
    assert_equal result.children.first.attributes.last.class, ::ORB::AST::Attribute
    assert_equal result.children.first.attributes.last.name, "id"
    assert_equal result.children.first.attributes.last.value, "main"
  end
  # rubocop:enable Metrics/AbcSize

  # Should be able to parse a tag with dynamic attributes
  def test_parse_tag_with_dynamic_attributes
    tokens = [
      ORB::Token.new(:tag_open, "div", { attributes: [["class", :expr, "container"], ["id", :expr, "unique_id"]] }),
      ORB::Token.new(:text, "Hello, World!"),
      ORB::Token.new(:tag_close, "div")
    ]

    parser = ORB::Parser.new(tokens)
    ast = parser.parse

    assert_equal ast.children.first.class, ORB::AST::TagNode
    assert       ast.children.first.static?
    assert_not ast.children.first.dynamic?
    assert_equal ast.children.first.static_attributes.size, 0
    assert_equal ast.children.first.splat_attributes.size, 0
    assert_equal ast.children.first.dynamic_attributes.size, 2
  end

  # Should be able to parse a tag with directives
  # rubocop:disable Metrics/AbcSize
  def test_parse_tag_with_directives
    tokens = [
      ORB::Token.new(:tag_open, "div", { attributes: [[":if", :expr, "items.any?"], ["class", :str, "container"]] }),
      ORB::Token.new(:text, "Hello, World!"),
      ORB::Token.new(:tag_close, "div")
    ]

    parser = ORB::Parser.new(tokens)
    ast = parser.parse

    assert       ast.children.first.class, ORB::AST::TagNode
    assert       ast.children.first.static?
    assert       ast.children.first.directives?
    assert       ast.children.first.compiler_directives?
    assert_not   ast.children.first.dynamic?
    assert_equal ast.children.first.directives.size, 1
    assert_equal ast.children.first.directives.first, [:if, "items.any?"]
    assert_equal ast.children.first.static_attributes.size, 1
    assert_equal ast.children.first.static_attributes.first.name, "class"
    assert_equal ast.children.first.static_attributes.first.type, :str
    assert_equal ast.children.first.static_attributes.first.value, "container"
    assert_equal ast.children.first.dynamic_attributes.size, 0
  end
  # rubocop:enable Metrics/AbcSize
end
