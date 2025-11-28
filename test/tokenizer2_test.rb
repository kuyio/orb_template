# frozen_string_literal: true

require_relative 'test_helper'

class Tokenizer2Test < Minitest::Test
  def test_tokenize_text
    source = "This is some text"
    tokenizer = ORB::Tokenizer2.new(source)
    tokens = tokenizer.tokenize

    assert_equal tokens, [
      ORB::Token.new(:text, "This is some text", line: 1, column: 1)
    ]
  end

  def test_tokenize_text_with_newline
    source = <<~TEXT
      This is some
      placeholder text
    TEXT
    tokenizer = ORB::Tokenizer2.new(source)
    tokens = tokenizer.tokenize

    assert_equal tokens, [
      ORB::Token.new(:text, "This is some", line: 1, column: 1),
      ORB::Token.new(:newline, "\n", line: 1, column: 13),
      ORB::Token.new(:text, "placeholder text", line: 2, column: 1),
      ORB::Token.new(:newline, "\n", line: 2, column: 17)
    ]
  end

  def test_tokenize_public_comment
    source = "<!-- This is a public comment -->"
    tokenizer = ORB::Tokenizer2.new(source)
    tokens = tokenizer.tokenize

    assert_equal tokens, [
      ORB::Token.new(:public_comment, " This is a public comment ", line: 1, column: 1)
    ]
  end

  def test_tokenize_private_comment
    source = "{!-- This is a private comment --}"
    tokenizer = ORB::Tokenizer2.new(source)
    tokens = tokenizer.tokenize

    assert_equal tokens, [
      ORB::Token.new(:private_comment, " This is a private comment ", line: 1, column: 1)
    ]
  end

  def test_tokenize_if_block
    input = "{#if true}Hello, World!{/if }"
    tokenizer = ORB::Tokenizer2.new(input)
    tokens = tokenizer.tokenize

    assert_equal tokens, [
      ORB::Token.new(:block_open, "if", line: 1, column: 1, expression: "true"),
      ORB::Token.new(:text, "Hello, World!", line: 1, column: 11),
      ORB::Token.new(:block_close, "if", line: 1, column: 24)
    ]
  end

  def test_tokenize_printing_expression
    source = "Hello, {{ name }}!"
    tokenizer = ORB::Tokenizer2.new(source)
    tokens = tokenizer.tokenize

    assert_equal tokens, [
      ORB::Token.new(:text, "Hello, ", line: 1, column: 1),
      ORB::Token.new(:printing_expression, "name", line: 1, column: 8),
      ORB::Token.new(:text, "!", line: 1, column: 18)
    ]
  end

  def test_tokenize_control_expression
    source = "Hello, {% name %}!"
    tokenizer = ORB::Tokenizer2.new(source)
    tokens = tokenizer.tokenize

    assert_equal tokens, [
      ORB::Token.new(:text, "Hello, ", line: 1, column: 1),
      ORB::Token.new(:control_expression, "name", line: 1, column: 8),
      ORB::Token.new(:text, "!", line: 1, column: 18)
    ]
  end

  def test_tokenize_simple_tag
    source = "<div>Hello, World!</div>"
    tokenizer = ORB::Tokenizer2.new(source)
    tokens = tokenizer.tokenize

    assert_equal tokens, [
      ORB::Token.new(:tag_open, "div", line: 1, column: 1, self_closing: false),
      ORB::Token.new(:text, "Hello, World!", line: 1, column: 6),
      ORB::Token.new(:tag_close, "div", line: 1, column: 19)
    ]
  end

  def test_tokenize_self_closing_tag_html
    source = "<br/>"
    tokenizer = ORB::Tokenizer2.new(source)
    tokens = tokenizer.tokenize

    assert_equal tokens, [
      ORB::Token.new(:tag_open, "br", line: 1, column: 1, self_closing: true)
    ]
  end

  def test_tokenize_self_closing_tag_xhtml
    source = "<br />"
    tokenizer = ORB::Tokenizer2.new(source)
    tokens = tokenizer.tokenize

    assert_equal tokens, [
      ORB::Token.new(:tag_open, "br", line: 1, column: 1, self_closing: true)
    ]
  end

  def test_tokenize_tag_with_single_quoted_attribute
    source = "<div class='test'/>"
    tokenizer = ORB::Tokenizer2.new(source)
    tokens = tokenizer.tokenize

    assert_equal tokens, [
      ORB::Token.new(
        :tag_open, "div", line: 1, column: 1, self_closing: true,
        attributes: [["class", :string, "test"]]
      )
    ]
  end

  def test_tokenize_tag_with_double_quoted_attribute
    source = '<div class="test"/>'
    tokenizer = ORB::Tokenizer2.new(source)
    tokens = tokenizer.tokenize

    assert_equal tokens, [
      ORB::Token.new(
        :tag_open, "div", line: 1, column: 1, self_closing: true,
        attributes: [["class", :string, "test"]]
      )
    ]
  end

  def test_tokenize_tag_with_unquoted_attribute
    source = "<div class=test/>"
    tokenizer = ORB::Tokenizer2.new(source)
    tokens = tokenizer.tokenize

    assert_equal tokens, [
      ORB::Token.new(
        :tag_open, "div", line: 1, column: 1, self_closing: true,
        attributes: [["class", :string, "test"]]
      )
    ]
  end

  def test_tokenize_tag_with_expression_attribute
    source = "<div class={ :test }/>"
    tokenizer = ORB::Tokenizer2.new(source)
    tokens = tokenizer.tokenize

    assert_equal tokens, [
      ORB::Token.new(:tag_open, "div", line: 1, column: 1, self_closing: true,
        attributes: [["class", :expression, ":test"]]
      )
    ]
  end

  def test_tokenize_tag_with_boolean_attribute
    source = "<div disabled/>"
    tokenizer = ORB::Tokenizer2.new(source)
    tokens = tokenizer.tokenize

    assert_equal tokens, [
      ORB::Token.new(:tag_open, "div", line: 1, column: 1, self_closing: true,
        attributes: [["disabled", :boolean, true]]
      )
    ]
  end

  def test_tokenize_tag_with_multiple_attributes
    source = "<div class='test' id=one disabled data-id={ dom_id(member) }/>"
    tokenizer = ORB::Tokenizer2.new(source)
    tokens = tokenizer.tokenize

    assert_equal tokens, [
      ORB::Token.new(:tag_open, "div", line: 1, column: 1, self_closing: true,
        attributes: [
          ["class", :string, "test"],
          ["id", :string, "one"],
          ["disabled", :boolean, true],
          ["data-id", :expression, "dom_id(member)"]
        ]
      )
    ]
  end

  def test_tokenize_tag_with_splat_attribute
    source = "<div class='test' *attrs/>"
    tokenizer = ORB::Tokenizer2.new(source)
    tokens = tokenizer.tokenize

    assert_equal tokens, [
      ORB::Token.new(:tag_open, "div", line: 1, column: 1, self_closing: true,
        attributes: [["class", :string, "test"], [nil, :splat, "*attrs"]]
      )
    ]
  end

  def test_tokenize_tag_with_expression_directive
    source = "<div :if={customer.active?}>Active</div>"
    tokenizer = ORB::Tokenizer2.new(source)
    tokens = tokenizer.tokenize

    assert_equal tokens, [
      ORB::Token.new(:tag_open, "div", line: 1, column: 1, self_closing: false,
        attributes: [[":if", :expression, "customer.active?"]]),
      ORB::Token.new(:text, "Active", line: 1, column: 29),
      ORB::Token.new(:tag_close, "div", line: 1, column: 35)
    ]
  end

  def test_tokenize_tag_with_empty_directive
    source = "<div :stimulus>Active</div>"
    tokenizer = ORB::Tokenizer2.new(source)
    tokens = tokenizer.tokenize

    assert_equal tokens, [
      ORB::Token.new(:tag_open, "div", line: 1, column: 1, self_closing: false,
        attributes: [[":stimulus", :boolean, true]]),
      ORB::Token.new(:text, "Active", line: 1, column: 16),
      ORB::Token.new(:tag_close, "div", line: 1, column: 22)
    ]
  end

  def test_tokenize_complex_html
    source = <<~ORB
      <div class="Test" disabled>
        <!-- I am a comment -->
        <p style={styles}>Hello, World!</p>
        {!-- and I am a private comment --}
        <br/>
      </div>
    ORB
    tokenizer = ORB::Tokenizer2.new(source)
    tokens = tokenizer.tokenize

    assert_equal tokens, [
      ORB::Token.new(:tag_open, "div", line: 1, column: 1, self_closing: false,
        attributes: [["class", :string, "Test"], ["disabled", :boolean, true]]),
      ORB::Token.new(:newline, "\n", line: 1, column: 28),
      ORB::Token.new(:text, "  ", line: 2, column: 1),
      ORB::Token.new(:public_comment, " I am a comment ", line: 2, column: 3),
      ORB::Token.new(:newline, "\n", line: 2, column: 26),
      ORB::Token.new(:text, "  ", line: 3, column: 1),
      ORB::Token.new(:tag_open, "p", line: 3, column: 3, self_closing: false,
        attributes: [["style", :expression, "styles"]]),
      ORB::Token.new(:text, "Hello, World!", line: 3, column: 21),
      ORB::Token.new(:tag_close, "p", line: 3, column: 34),
      ORB::Token.new(:newline, "\n", line: 3, column: 38),
      ORB::Token.new(:text, "  ", line: 4, column: 1),
      ORB::Token.new(:private_comment, " and I am a private comment ", line: 4, column: 3),
      ORB::Token.new(:newline, "\n", line: 4, column: 38),
      ORB::Token.new(:text, "  ", line: 5, column: 1),
      ORB::Token.new(:tag_open, "br", line: 5, column: 3, self_closing: true),
      ORB::Token.new(:newline, "\n", line: 5, column: 8),
      ORB::Token.new(:tag_close, "div", line: 6, column: 1),
      ORB::Token.new(:newline, "\n", line: 6, column: 9)
    ]
  end

  def test_tokenizes_a_slot_tag
    source = %q(<Card:section title="One">card section content</Card:section>)
    tokenizer = ORB::Tokenizer2.new(source)
    tokens = tokenizer.tokenize

    assert_equal tokens, [
      ORB::Token.new(:tag_open, "Card:section", line: 1, column: 1, self_closing: false,
        attributes: [["title", :string, "One"]]),
      ORB::Token.new(:text, "card section content", line: 1, column: 27),
      ORB::Token.new(:tag_close, "Card:section", line: 1, column: 47)
    ]
  end

  def test_tokenizes_verbatim_tag
    source = %q(<Verbatim$>This is <span>verbatim</span> content</Verbatim$>)
    tokenizer = ORB::Tokenizer2.new(source)
    tokens = tokenizer.tokenize

    assert_equal tokens, [
      ORB::Token.new(:tag_open, "Verbatim", line: 1, column: 1, self_closing: false, verbatim: true),
      ORB::Token.new(:text, "This is <span>verbatim</span> content", line: 1, column: 12),
      ORB::Token.new(:tag_close, "Verbatim", line: 1, column: 49)
    ]
  end
end
