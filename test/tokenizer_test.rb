# frozen_string_literal: true

require_relative "test_helper"

class TokenizerTest < Minitest::Test
  def test_tokenize_empty_string
    source = ""
    tokenizer = ::ORB::Tokenizer.new(source)
    tokenizer.tokenize

    assert_empty tokenizer.tokens
    assert_empty tokenizer.errors
  end

  def test_tokenize_simple_string
    source = "Hello, World!"
    tokenizer = ::ORB::Tokenizer.new(source)
    tokenizer.tokenize

    assert_equal tokenizer.tokens, [
      ::ORB::Token.new(:text, "Hello, World!")
    ]

    assert_empty tokenizer.errors
  end

  def test_tokenize_simple_html_tag
    source = "<p>Hello, World!</p>"
    tokenizer = ::ORB::Tokenizer.new(source)
    tokenizer.tokenize!

    assert_equal tokenizer.tokens, [
      ::ORB::Token.new(:tag_open, "p", { self_closing: false, attributes: [] }),
      ::ORB::Token.new(:text, "Hello, World!"),
      ::ORB::Token.new(:tag_close, "p")
    ]

    assert_empty tokenizer.errors
  end

  def test_tokenize_self_closing_html_tag
    source = "<br/>"
    tokenizer = ::ORB::Tokenizer.new(source)
    tokenizer.tokenize

    assert_equal tokenizer.tokens, [
      ::ORB::Token.new(:tag_open, "br", { self_closing: true, attributes: [] })
    ]

    assert_empty tokenizer.errors
  end

  def test_tokenize_unclosed_html_tag
    source = "<p>Hello, World!"
    tokenizer = ::ORB::Tokenizer.new(source)

    assert_raises(ORB::SyntaxError) do
      tokenizer.tokenize
    end
  end

  def test_tokenize_boolean_html_attribute
    source = "<input disabled/>"
    tokenizer = ::ORB::Tokenizer.new(source)
    tokenizer.tokenize

    assert_equal tokenizer.tokens, [
      ::ORB::Token.new(:tag_open, "input", { self_closing: true, attributes: [["disabled", :bool, true]] })
    ]

    assert_empty tokenizer.errors
  end

  def test_tokenize_single_quoted_html_attribute
    source = "<input type='text'/>"
    tokenizer = ::ORB::Tokenizer.new(source)
    tokenizer.tokenize

    assert_equal tokenizer.tokens, [
      ::ORB::Token.new(:tag_open, "input", { self_closing: true, attributes: [["type", :str, "text"]] })
    ]

    assert_empty tokenizer.errors
  end

  def test_tokenize_double_quoted_html_attribute
    source = '<input type="text"/>'
    tokenizer = ::ORB::Tokenizer.new(source)
    tokenizer.tokenize

    assert_equal tokenizer.tokens, [
      ::ORB::Token.new(:tag_open, "input", { self_closing: true, attributes: [["type", :str, "text"]] })
    ]

    assert_empty tokenizer.errors
  end

  def test_tokenize_dynamic_html_attribute
    source = "<div class={classes} />"
    tokenizer = ::ORB::Tokenizer.new(source)
    tokenizer.tokenize

    assert_equal tokenizer.tokens, [
      ::ORB::Token.new(:tag_open, "div", { self_closing: true, attributes: [["class", :expr, "classes"]] })
    ]

    assert_empty tokenizer.errors
  end

  def test_tokenize_single_quoted_html_attribute_with_expression
    source = "<div class='{{classes}}' />"
    tokenizer = ::ORB::Tokenizer.new(source)
    tokenizer.tokenize

    # TODO: Update this test case when we support expressions in single-quoted attributes
    assert_equal tokenizer.tokens, [
      ::ORB::Token.new(:tag_open, "div", { self_closing: true, attributes: [["class", :str, "{{classes}}"]] })
    ]

    assert_empty tokenizer.errors
  end

  def test_tokenize_double_quoted_html_attribute_with_expression
    source = '<div class="{{classes}}" />'
    tokenizer = ::ORB::Tokenizer.new(source)
    tokenizer.tokenize

    # TODO: Update this test case when we support expressions in double-quoted attributes
    assert_equal tokenizer.tokens, [
      ::ORB::Token.new(:tag_open, "div", { self_closing: true, attributes: [["class", :str, "{{classes}}"]] })
    ]

    assert_empty tokenizer.errors
  end

  def test_tokenize_simple_string_with_printing_expression
    source = "Hello, {{name}}!"
    tokenizer = ::ORB::Tokenizer.new(source)
    tokenizer.tokenize!

    assert_equal tokenizer.tokens, [
      ::ORB::Token.new(:text, "Hello, "),
      ::ORB::Token.new(:printing_expression, "name", {}),
      ::ORB::Token.new(:text, "!")
    ]

    assert_empty tokenizer.errors
  end

  def test_tokenize_simple_string_with_printing_expression_inside_if_block
    source = "Hello, {#if name}{{name}}{/if}!"
    tokenizer = ::ORB::Tokenizer.new(source)
    tokenizer.tokenize!

    assert_equal tokenizer.tokens, [
      ::ORB::Token.new(:text, "Hello, "),
      ::ORB::Token.new(:block_open, "if", { expression: "name" }),
      ::ORB::Token.new(:printing_expression, "name", {}),
      ::ORB::Token.new(:block_close, "if", {}),
      ::ORB::Token.new(:text, "!")
    ]

    assert_empty tokenizer.errors
  end

  def test_tokenize_simple_string_with_malformed_printing_expression_inside_if_block
    source = "Hello, {#if name}{{name}{/if}!"
    tokenizer = ::ORB::Tokenizer.new(source)

    assert_raises(ORB::SyntaxError) { tokenizer.tokenize }
  end

  def test_tokenize_simple_string_with_unclosed_if_block
    source = "Hello, {#if name}{{name}}!"
    tokenizer = ::ORB::Tokenizer.new(source)

    assert_raises(ORB::SyntaxError) { tokenizer.tokenize }
  end

  def test_tokenize_simple_string_with_non_printing_expression
    source = "Hello {% name = 'John' %}!"
    tokenizer = ::ORB::Tokenizer.new(source)
    tokenizer.tokenize

    assert_equal tokenizer.tokens, [
      ::ORB::Token.new(:text, "Hello "),
      ::ORB::Token.new(:control_expression, "name = 'John'"),
      ::ORB::Token.new(:text, "!")
    ]
  end

  def test_tokenize_nested_html_tags
    source = <<~HTML
      <div>
        <p>Hello, World!</p>
        <p>Goodbye, World!</p>
      </div>
    HTML

    tokenizer = ::ORB::Tokenizer.new(source)
    tokenizer.tokenize

    assert_equal tokenizer.tokens, [
      ::ORB::Token.new(:tag_open, "div", { self_closing: false, attributes: [] }),
      ::ORB::Token.new(:text, "\n  "),
      ::ORB::Token.new(:tag_open, "p", { self_closing: false, attributes: [] }),
      ::ORB::Token.new(:text, "Hello, World!"),
      ::ORB::Token.new(:tag_close, "p"),
      ::ORB::Token.new(:text, "\n  "),
      ::ORB::Token.new(:tag_open, "p", { self_closing: false, attributes: [] }),
      ::ORB::Token.new(:text, "Goodbye, World!"),
      ::ORB::Token.new(:tag_close, "p"),
      ::ORB::Token.new(:text, "\n"),
      ::ORB::Token.new(:tag_close, "div")
    ]

    assert_empty tokenizer.errors
  end

  def test_tokenize_public_comment
    source = <<~HTML
      <!-- This is a comment -->
      <p>Hello, World!</p>
    HTML

    tokenizer = ::ORB::Tokenizer.new(source)
    tokenizer.tokenize

    assert_equal tokenizer.tokens, [
      ::ORB::Token.new(:public_comment, " This is a comment "),
      ::ORB::Token.new(:text, "\n"),
      ::ORB::Token.new(:tag_open, "p", { self_closing: false, attributes: [] }),
      ::ORB::Token.new(:text, "Hello, World!"),
      ::ORB::Token.new(:tag_close, "p")
    ]

    assert_empty tokenizer.errors
  end

  def test_tokenize_private_comment
    source = <<~HTML
      {!-- This is a comment --}
      <p>Hello, World!</p>
    HTML

    tokenizer = ::ORB::Tokenizer.new(source)
    tokenizer.tokenize

    assert_equal tokenizer.tokens, [
      ::ORB::Token.new(:private_comment, " This is a comment "),
      ::ORB::Token.new(:text, "\n"),
      ::ORB::Token.new(:tag_open, "p", { self_closing: false, attributes: [] }),
      ::ORB::Token.new(:text, "Hello, World!"),
      ::ORB::Token.new(:tag_close, "p")
    ]

    assert_empty tokenizer.errors
  end

  def test_tokenize_whitespace_between_expressions_is_preserved
    source = "{{'John'}} {{'Doe'}}"
    tokenizer = ::ORB::Tokenizer.new(source)
    tokenizer.tokenize

    assert_equal tokenizer.tokens, [
      ::ORB::Token.new(:printing_expression, "'John'", {}),
      ::ORB::Token.new(:text, " "),
      ::ORB::Token.new(:printing_expression, "'Doe'", {})
    ]
  end

  def test_tokenize_void_tags_without_requiring_closing_tag
    source = "<div><br><hr><img><input><link><meta></div>"
    tokenizer = ::ORB::Tokenizer.new(source)
    tokens = tokenizer.tokenize

    assert_equal tokens, [
      ORB::Token.new(:tag_open, "div", { self_closing: false, attributes: [] }),
      ORB::Token.new(:tag_open, "br", { self_closing: true, attributes: [] }),
      ORB::Token.new(:tag_open, "hr", { self_closing: true, attributes: [] }),
      ORB::Token.new(:tag_open, "img", { self_closing: true, attributes: [] }),
      ORB::Token.new(:tag_open, "input", { self_closing: true, attributes: [] }),
      ORB::Token.new(:tag_open, "link", { self_closing: true, attributes: [] }),
      ORB::Token.new(:tag_open, "meta", { self_closing: true, attributes: [] }),
      ORB::Token.new(:tag_close, "div")
    ]
  end
end
