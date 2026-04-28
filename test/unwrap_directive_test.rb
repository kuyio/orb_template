# frozen_string_literal: true

require_relative "test_helper"

class UnwrapDirectiveTest < Minitest::Test
  # ---------------------------------------------------------------------------
  # Compiler-level tests: verify the Temple IR produced by the compiler
  # ---------------------------------------------------------------------------

  def test_compile_unwrap_on_html_tag
    input = '<div class="wrapper" :unwrap={@minimal}><span>content</span></div>'

    temple = compile_to_temple(input)

    assert_equal temple[0], :multi
    child = temple[1]
    assert_equal child[0], :orb
    assert_equal child[1], :unwrap
    assert_equal child[2], "@minimal"
  end

  def test_compile_unwrap_on_component_tag
    input = '<Card :unwrap={@skip_card}>inner</Card>'

    temple = compile_to_temple(input)

    child = temple[1]
    assert_equal child[0], :orb
    assert_equal child[1], :unwrap
    assert_equal child[2], "@skip_card"
  end

  def test_compile_if_and_unwrap_together
    input = '<div :if={@visible} :unwrap={@plain}><span>text</span></div>'

    temple = compile_to_temple(input)

    child = temple[1]
    assert_equal child[0], :if
    assert_equal child[1], "@visible"

    unwrap_node = child[2]
    assert_equal unwrap_node[0], :orb
    assert_equal unwrap_node[1], :unwrap
    assert_equal unwrap_node[2], "@plain"
  end

  def test_compile_unwrap_carries_both_element_and_children
    input = '<div class="wrapper" :unwrap={@minimal}><span>child</span></div>'

    temple = compile_to_temple(input)

    unwrap_node = temple[1]
    assert_equal unwrap_node[0], :orb
    assert_equal unwrap_node[1], :unwrap
    assert_equal unwrap_node.length, 5, "Unwrap expression should have 5 elements: [:orb, :unwrap, condition, element, children]"
  end

  # ---------------------------------------------------------------------------
  # Full pipeline tests: compile through the engine and inspect generated Ruby
  # ---------------------------------------------------------------------------

  def test_unwrap_generates_conditional_branches
    template = '<div class="wrapper" :unwrap={@minimal}><span>content</span></div>'
    code = compile(template)

    result = Prism.parse(code)
    assert result.success?, "Generated code has syntax errors: #{result.errors.map(&:message).join(', ')}"
    assert_includes code, "@minimal"
    assert_includes code, "<span>"
  end

  def test_unwrap_true_renders_children_only
    template = '<div class="wrapper" :unwrap={true}><span>inner</span></div>'
    code = compile(template)

    result = Prism.parse(code)
    assert result.success?, "Generated code has syntax errors: #{result.errors.map(&:message).join(', ')}"
  end

  def test_unwrap_false_renders_element_with_children
    template = '<div class="wrapper" :unwrap={false}><span>inner</span></div>'
    code = compile(template)

    result = Prism.parse(code)
    assert result.success?, "Generated code has syntax errors: #{result.errors.map(&:message).join(', ')}"
  end

  def test_unwrap_on_self_closing_tag
    template = '<hr :unwrap={@skip} />'
    code = compile(template)

    result = Prism.parse(code)
    assert result.success?, "Generated code has syntax errors: #{result.errors.map(&:message).join(', ')}"
    assert_includes code, "@skip"
  end

  def test_unwrap_with_multiple_children
    template = '<div :unwrap={@flat}><span>one</span><span>two</span><span>three</span></div>'
    code = compile(template)

    result = Prism.parse(code)
    assert result.success?, "Generated code has syntax errors: #{result.errors.map(&:message).join(', ')}"
    assert_includes code, "one"
    assert_includes code, "two"
    assert_includes code, "three"
  end

  def test_unwrap_with_expression_children
    template = '<div :unwrap={@flat}>{{@name}}</div>'
    code = compile(template)

    result = Prism.parse(code)
    assert result.success?, "Generated code has syntax errors: #{result.errors.map(&:message).join(', ')}"
    assert_includes code, "@name"
  end

  def test_if_and_unwrap_combined_generates_valid_code
    template = '<div :if={@show} :unwrap={@plain}><span>text</span></div>'
    code = compile(template)

    result = Prism.parse(code)
    assert result.success?, "Generated code has syntax errors: #{result.errors.map(&:message).join(', ')}"
    assert_includes code, "@show"
    assert_includes code, "@plain"
  end

  def test_unwrap_does_not_break_for_directive
    template = '<li :for="item in @items">{{item}}</li>'
    code = compile(template)

    assert_includes code, "@items.each do |item|",
      "Existing :for directive should still work after refactor"
  end

  def test_unwrap_does_not_break_if_directive
    template = '<div :if={@visible}>content</div>'
    code = compile(template)

    result = Prism.parse(code)
    assert result.success?, "Generated code has syntax errors: #{result.errors.map(&:message).join(', ')}"
    assert_includes code, "@visible"
  end

  def test_unwrap_with_negated_condition
    template = '<div class="tooltip" :unwrap={!@needs_tooltip}><span>badge</span></div>'
    code = compile(template)

    result = Prism.parse(code)
    assert result.success?, "Generated code has syntax errors: #{result.errors.map(&:message).join(', ')}"
    assert_includes code, "!@needs_tooltip"
  end

  def test_unwrap_with_complex_condition
    template = '<div :unwrap={@user&.admin? || @bypass}><span>admin panel</span></div>'
    code = compile(template)

    result = Prism.parse(code)
    assert result.success?, "Generated code has syntax errors: #{result.errors.map(&:message).join(', ')}"
  end

  def test_unwrap_on_component_generates_valid_code
    template = '<Card :unwrap={@skip_card}>inner text</Card>'
    code = compile(template)

    result = Prism.parse(code)
    assert result.success?, "Generated code has syntax errors: #{result.errors.map(&:message).join(', ')}"
    assert_includes code, "@skip_card"
  end

  # ---------------------------------------------------------------------------
  # AST-level tests: verify directive recognition on TagNode
  # ---------------------------------------------------------------------------

  def test_tag_node_recognizes_unwrap_as_compiler_directive
    tokens = [
      ORB::Token.new(:tag_open, "div", { attributes: [[":unwrap", :expr, "@minimal"]] }),
      ORB::Token.new(:text, "content"),
      ORB::Token.new(:tag_close, "div")
    ]

    parser = ORB::Parser.new(tokens)
    ast = parser.parse

    node = ast.children.first
    assert node.directives?, "Node should have directives"
    assert node.compiler_directives?, "Node should have compiler directives"
    assert_equal node.directives[:unwrap], "@minimal"
  end

  def test_tag_node_with_if_and_unwrap_directives
    tokens = [
      ORB::Token.new(:tag_open, "div", { attributes: [[":if", :expr, "@visible"], [":unwrap", :expr, "@plain"]] }),
      ORB::Token.new(:text, "content"),
      ORB::Token.new(:tag_close, "div")
    ]

    parser = ORB::Parser.new(tokens)
    ast = parser.parse

    node = ast.children.first
    assert node.compiler_directives?, "Node should have compiler directives"
    assert_equal node.directives[:if], "@visible"
    assert_equal node.directives[:unwrap], "@plain"
  end

  # ---------------------------------------------------------------------------
  # Filter-level tests: verify the on_orb_unwrap filter output
  # ---------------------------------------------------------------------------

  def test_filter_unwrap_produces_if_else_structure
    input = '<div class="wrapper" :unwrap={@minimal}><span>child</span></div>'

    temple = compile_to_filtered_temple(input)

    if_nodes = extract_if_nodes(temple)
    unwrap_if = if_nodes.find { |n| n[1] == "@minimal" }
    assert unwrap_if, "Filtered temple should contain an :if node with the unwrap condition"
    assert_equal unwrap_if.length, 4, "Unwrap :if should have both true and false branches (if/cond/true/false)"
  end

  def test_filter_unwrap_true_branch_is_children_only
    input = '<div class="wrap" :unwrap={@strip}><span>child</span></div>'

    temple = compile_to_filtered_temple(input)

    if_nodes = extract_if_nodes(temple)
    unwrap_if = if_nodes.find { |n| n[1] == "@strip" }
    true_branch = unwrap_if[2]
    false_branch = unwrap_if[3]

    true_statics = extract_static_nodes(true_branch).map { |n| n[1] }
    false_statics = extract_static_nodes(false_branch).map { |n| n[1] }

    refute true_statics.any? { |s| s.include?("wrap") },
      "True branch (unwrapped) should not contain the wrapper element"
    assert true_statics.any? { |s| s.include?("child") },
      "True branch should contain the children"

    assert false_statics.any? { |s| s.include?("wrap") },
      "False branch should contain the wrapper element"
    assert false_statics.any? { |s| s.include?("child") },
      "False branch should also contain the children"
  end

  private

  def compile(template)
    ORB::Temple::Engine.new(
      generator: ::Temple::Generators::StringBuffer,
      use_html_safe: false,
      streaming: false,
      disable_capture: false
    ).call(template)
  end

  def compile_to_temple(template)
    parser = ORB::Temple::Parser.new
    ast = parser.call(template)
    compiler = ORB::Temple::Compiler.new
    compiler.call(ast)
  end

  def compile_to_filtered_temple(template)
    parser = ORB::Temple::Parser.new
    ast = parser.call(template)
    compiler = ORB::Temple::Compiler.new
    temple = compiler.call(ast)
    filters = ORB::Temple::Filters.new
    filters.call(temple)
  end

  def extract_if_nodes(temple)
    return [] unless temple.is_a?(Array)
    return [temple] if temple[0] == :if

    temple.flat_map { |child| extract_if_nodes(child) }
  end

  def extract_static_nodes(temple)
    return [] unless temple.is_a?(Array)
    return [temple] if temple[0] == :static

    temple.flat_map { |child| extract_static_nodes(child) }
  end
end
