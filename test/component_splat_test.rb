# frozen_string_literal: true

require_relative 'test_helper'

class ComponentSplatTest < ActiveSupport::TestCase
  # When a component has splat attributes, the compiler should generate
  # [:orb, :dynamic] which the filter should then route to on_orb_component
  def test_component_with_splat_attributes_compiles_correctly
    input = <<-ORB
      {% attrs = {title: "Test Card"} %}
      <Card **attrs>
        <p>Content</p>
      </Card>
    ORB

    # Parse and compile
    parser = ORB::Temple::Parser.new
    ast = parser.call(input)
    compiler = ORB::Temple::Compiler.new
    temple = compiler.call(ast)

    # Find the [:orb, :dynamic, ...] expression in the temple output
    dynamic_expr = find_orb_expression(temple, :dynamic)

    assert_not_nil dynamic_expr, "Expected to find [:orb, :dynamic, ...] expression"
    assert_equal dynamic_expr[1], :dynamic

    # The node should be a component tag
    node = dynamic_expr[2]
    assert node.component_tag?, "Expected node to be identified as a component tag"
    assert_equal node.tag, "Card"
    assert_equal node.splat_attributes.length, 1
  end

  # Test that the filter properly routes dynamic component tags to on_orb_component
  def test_filter_routes_dynamic_component_to_component_handler
    input = "<Card **attrs><p>Test</p></Card>"

    # Parse to get the AST
    parser = ORB::Temple::Parser.new
    ast = parser.call(input)

    # Compile to get temple expressions
    compiler = ORB::Temple::Compiler.new
    temple = compiler.call(ast)

    # Apply filters
    filter = ORB::Temple::Filters.new
    filtered = filter.call(temple)

    # The filtered output should contain component rendering code, not content_tag
    filtered_str = filtered.to_s

    # Should contain "render" and "Card" (component rendering)
    assert filtered_str.include?("render"), "Expected filtered output to contain 'render'"
    assert filtered_str.include?("Card"), "Expected filtered output to contain 'Card'"

    # Should NOT contain "content_tag" with lowercase 'card'
    assert_not filtered_str.include?("content_tag('card'"), "Should not render as lowercase HTML tag"
    assert_not filtered_str.include?('content_tag("card"'), "Should not render as lowercase HTML tag"
  end

  private

  # Recursive helper to find an [:orb, type, ...] expression in temple output
  def find_orb_expression(expr, type)
    return nil unless expr.is_a?(Array)
    return expr if expr[0] == :orb && expr[1] == type

    expr.each do |child|
      result = find_orb_expression(child, type)
      return result if result
    end

    nil
  end
end
