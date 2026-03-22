# frozen_string_literal: true

require_relative "test_helper"

class EngineCodegenTest < Minitest::Test
  # Compile an ORB template through the full engine pipeline using the
  # same generator options that RailsTemplate uses. This exercises the
  # AttributeRemover filter which wraps dynamic attributes in :capture
  # nodes - a code path that unit tests on the compiler alone don't hit.
  def test_dynamic_class_attribute_produces_no_void_context_variable
    source = '<div class={classes}>Hello</div>'
    code = compile(source)

    # The generated Ruby must be syntactically valid
    result = Prism.parse(code)
    assert result.success?, "Generated code has syntax errors: #{result.errors.map(&:message).join(', ')}"

    # Ruby -w warns "possibly useless use of a variable in void context"
    # when a bare variable sits as a standalone expression. Detect this
    # by checking that no temp variable appears as a bare statement
    # (i.e. preceded by "; " and followed by ";" without an assignment,
    # method call, or conditional).
    bare_variable = /; (_temple_\w+); /
    refute_match bare_variable, code,
      "Generated code contains a variable in void context — will trigger Ruby -w warning"
  end

  def test_dynamic_id_attribute_produces_no_void_context_variable
    source = '<div id={dom_id}>Hello</div>'
    code = compile(source)

    bare_variable = /; (_temple_\w+); /
    refute_match bare_variable, code,
      "Generated code contains a variable in void context — will trigger Ruby -w warning"
  end

  def test_multiple_dynamic_removable_attributes
    source = '<div class={classes} id={dom_id}>Hello</div>'
    code = compile(source)

    bare_variable = /; (_temple_\w+); /
    refute_match bare_variable, code,
      "Generated code contains a variable in void context — will trigger Ruby -w warning"
  end

  def test_static_class_attribute_unaffected
    source = '<div class="static">Hello</div>'
    code = compile(source)

    result = Prism.parse(code)
    assert result.success?, "Generated code has syntax errors: #{result.errors.map(&:message).join(', ')}"
  end

  private

  def compile(source)
    ORB::Temple::Engine.new(ORB::RailsTemplate.options).call(source)
  end
end
