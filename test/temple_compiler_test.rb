# frozen_string_literal: true

require_relative 'test_helper'

class TempleCompilerTest < Minitest::Test
  # When calling the compiler with an empty string, the resulting temple
  # expression should be an empty multi-node
  def test_compile_empty_string
    input = ""

    parser = ORB::Temple::Parser.new
    ast = parser.call(input)
    compiler = ORB::Temple::Compiler.new
    temple = compiler.call(ast)

    assert_equal temple, [:multi]
  end

  # When calling the compiler with a simple string, the resulting temple
  # expression should be a multi node with single static node child
  # containing the string as its value
  def test_compile_text
    input = "Hello, World!"

    parser = ORB::Temple::Parser.new
    ast = parser.call(input)
    compiler = ORB::Temple::Compiler.new
    temple = compiler.call(ast)

    assert_equal temple, [:multi,
      [:static, "Hello, World!"]]
  end

  # When calling the compiler with a string containing a printing expression,
  # the resulting temple expression should be a multi node the escaped dynamic
  # expression surrounded by the text static nodes
  def test_compile_printing_expression
    input = "Hello, {{name}}!"

    parser = ORB::Temple::Parser.new
    ast = parser.call(input)
    compiler = ORB::Temple::Compiler.new
    temple = compiler.call(ast)

    assert_equal temple, [:multi,
      [:static, "Hello, "],
      [:escape, true, [:dynamic, "name"]],
      [:static, "!"]]
  end

  # When calling the compiler with a string containing a printing expression
  # with a block, the resulting temple expression should be a multi node with
  # the escaped dynamic expression surrounded by the text static nodes
  def test_compile_printing_expression_with_block
    input = <<~ORB
      {{ [1,2,3].each do |i| }}
        {{i}}
      {{ end }}
    ORB

    parser = ORB::Temple::Parser.new
    ast = parser.call(input)
    compiler = ORB::Temple::Compiler.new
    temple = compiler.call(ast)

    assert_equal temple, [
      :multi, [
        :multi, [
          :block, "_orb_compiler_variable_1 = [1,2,3].each do |i|", [:capture, "_orb_compiler_variable_2", [
            :multi, [:newline], [:static, "  "], [:escape, true, [:dynamic, "i"]], [:newline]
          ]]
        ],
        [:escape, true, [:dynamic, "_orb_compiler_variable_1"]]
      ],
      [:newline]
    ]
  end

  # When calling the compiler with a string containing an #if block, the
  # resulting temple expression should be a multi node with static text
  # nodes and a [:orb, :if] node with the condition and the body as its children
  def test_compile_if_block
    input = "Hello {#if name}{{name}}{/if}!"

    parser = ORB::Temple::Parser.new
    ast = parser.call(input)
    compiler = ORB::Temple::Compiler.new
    temple = compiler.call(ast)

    assert_equal temple, [:multi,
      [:static, "Hello "],
      [:orb, :if, "name", [:multi, [:escape, true, [:dynamic, "name"]]]],
      [:static, "!"]]
  end

  # TODO: Test compiling a #for block node into a Temple expression

  # When calling the compiler with a comment, the resulting temple expression
  # should be a multi node with a comment node as its child
  def test_compile_comment
    input = "<!-- Say Hello -->"

    parser = ORB::Temple::Parser.new
    ast = parser.call(input)
    compiler = ORB::Temple::Compiler.new
    temple = compiler.call(ast)

    assert_equal temple, [:multi,
      [:html, :comment, [:static, " Say Hello "]]]
  end

  # TODO: Test compiling a private_comment node into a Temple expression

  # When calling the compiler with an HTML tag, the resulting temple
  # expression should be a multi node with an [:orb, :tag] node as its child
  def test_compile_html_tag
    input = "<div>Hello, World!</div>"

    parser = ORB::Temple::Parser.new
    ast = parser.call(input)
    compiler = ORB::Temple::Compiler.new
    temple = compiler.call(ast)

    assert_equal temple, [:multi, [:orb, :tag, "div", [], [:multi, [:static, "Hello, World!"]]]]
  end

  # TODO: Test compiling a void HTML tag node into a Temple expression

  # TODO: Test compiling a component tag node into a Temple expression

  # When calling the compiler with a component tag with splat attributes,
  # the resulting temple expression should be a multi node with an [:orb, :dynamic]
  # node (dynamic tags have splat attributes). The filter will then determine
  # if it's a component or HTML tag based on the node properties.
  def test_compile_component_with_splat_attributes
    input = "<Card **attrs>Hello</Card>"

    parser = ORB::Temple::Parser.new
    ast = parser.call(input)
    compiler = ORB::Temple::Compiler.new
    temple = compiler.call(ast)

    # The first child should be [:orb, :dynamic, node, content]
    # because the tag has splat attributes making it dynamic
    assert_equal temple[0], :multi
    assert_equal temple[1][0], :orb
    assert_equal temple[1][1], :dynamic

    # Verify the node itself is a component tag
    node = temple[1][2]
    assert node.component_tag?, "Expected a component tag node"
    assert_equal node.tag, "Card"
    assert_equal node.splat_attributes.length, 1
  end

  # Test compiling a component with both static and splat attributes
  def test_compile_component_with_mixed_attributes
    input = '<Card title="Static Title" **extra_attrs>Hello</Card>'

    parser = ORB::Temple::Parser.new
    ast = parser.call(input)
    compiler = ORB::Temple::Compiler.new
    temple = compiler.call(ast)

    # Should be dynamic due to splat attributes
    assert_equal temple[1][1], :dynamic

    # Verify the node has both static and splat attributes
    node = temple[1][2]
    assert node.component_tag?, "Expected a component tag node"
    # title + splat
    assert_equal node.attributes.length, 2
    assert_equal node.splat_attributes.length, 1

    # Verify static attribute
    title_attr = node.attributes.find { |a| a.name == "title" }
    assert title_attr, "Expected to find title attribute"
    assert_equal title_attr.value, "Static Title"
  end

  # TODO: Test compiling a component slot tag node into a Temple expression

  # Compile a :str attribute to a Temple [:html, :attr] expression
  def test_compile_str_attribute
    attribute = ::ORB::AST::Attribute.new("class", :str, "foo")
    compiler = ::ORB::Temple::AttributesCompiler.new
    temple = compiler.compile_attribute(attribute)

    assert_equal temple, [:html, :attr, "class", [:static, "foo"]]
  end

  # Compile a :bool attribute to a Temple [:html, :attr] expression
  def test_compile_bool_attribute
    attribute = ::ORB::AST::Attribute.new("disabled", :bool)
    compiler = ::ORB::Temple::AttributesCompiler.new
    temple = compiler.compile_attribute(attribute)

    assert_equal temple, [:html, :attr, "disabled", [:dynamic, "nil"]]
  end

  # Compile a :expr attribute to a Temple [:html, :attr] expression
  def test_compile_expr_attribute
    attribute = ::ORB::AST::Attribute.new("sum", :expr, "1 + 1")
    compiler = ::ORB::Temple::AttributesCompiler.new
    temple = compiler.compile_attribute(attribute)

    assert_equal temple, [:html, :attr, "sum", [:dynamic, "1 + 1"]]
  end

  # Test compiling a list of attributes into a Temple [:html, :attrs] expression
  def test_compile_attributes
    attributes = [
      ::ORB::AST::Attribute.new("class", :str, "foo"),
      ::ORB::AST::Attribute.new("disabled", :bool),
      ::ORB::AST::Attribute.new("sum", :expr, "1 + 1")
    ]
    compiler = ::ORB::Temple::AttributesCompiler.new
    temple = compiler.compile_attributes(attributes)

    assert_equal temple, [:html, :attrs,
      [:html, :attr, "class", [:static, "foo"]],
      [:html, :attr, "disabled", [:dynamic, "nil"]],
      [:html, :attr, "sum", [:dynamic, "1 + 1"]]]
  end

  # Test compiling a list of attributes into a list of captures
  def test_compile_attributes_to_captures
    attributes = [
      ::ORB::AST::Attribute.new("class", :str, "foo"),
      ::ORB::AST::Attribute.new("disabled", :bool),
      ::ORB::AST::Attribute.new("sum", :expr, "1 + 1")
    ]
    compiler = ::ORB::Temple::AttributesCompiler.new
    captures = compiler.compile_captures(attributes, "tst")

    assert_equal captures, [
      [:code, "tst_arg_class = \"foo\""],
      [:code, "tst_arg_disabled = true"],
      [:code, "tst_arg_sum = 1 + 1"]
    ]
  end

  # Test compiling a list of attributes into a list of view component arguments
  def test_compile_attributes_to_komponent_args
    attributes = [
      ::ORB::AST::Attribute.new("class", :str, "foo"),
      ::ORB::AST::Attribute.new("disabled", :bool),
      ::ORB::AST::Attribute.new("sum", :expr, "1 + 1")
    ]
    compiler = ::ORB::Temple::AttributesCompiler.new
    args = compiler.compile_komponent_args(attributes, "tst")

    assert_equal args, "class: tst_arg_class, disabled: tst_arg_disabled, sum: tst_arg_sum"
  end

  # Attribute names that contain a dash should be collected into a hash
  def test_compile_dashed_attributes_to_hash_capture
    attributes = [
      ::ORB::AST::Attribute.new("class", :str, "List"),
      ::ORB::AST::Attribute.new("data-one", :str, "1"),
      ::ORB::AST::Attribute.new("data-two", :bool),
      ::ORB::AST::Attribute.new("data-three", :expr, "3*2")
    ]
    compiler = ::ORB::Temple::AttributesCompiler.new
    captures = compiler.compile_captures(attributes, "tst")

    assert_equal captures, [
      [:code, "tst_arg_class = \"List\""],
      [:code, "tst_arg_data_one = \"1\""],
      [:code, "tst_arg_data_two = true"],
      [:code, "tst_arg_data_three = 3*2"]
    ]
  end

  def test_compile_dashed_attributes_komponent_args
    attributes = [
      ::ORB::AST::Attribute.new("aria-label", :str, "List"),
      ::ORB::AST::Attribute.new("aria-role", :str, "popover")
    ]
    compiler = ::ORB::Temple::AttributesCompiler.new
    args = compiler.compile_komponent_args(attributes, "tst")

    assert_equal args, "aria: {label: tst_arg_aria_label, role: tst_arg_aria_role}"
  end
end
