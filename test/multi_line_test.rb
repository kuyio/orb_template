# frozen_string_literal: true

require_relative 'test_helper'
require 'tilt'

class MultiLineTest < Minitest::Test
  # When calling the compiler with an empty string, the resulting temple
  # expression should be an empty multi-node
  def test_compiles_and_renders_multiline_string
    input = File.read(File.join(__dir__, 'fixtures', 'multiline.orb'))

    # It parses multi-line expressions correctly
    parser = ORB::Temple::Parser.new
    ast = parser.call(input)

    # It compiles multi-line expressions correctly
    compiler = ORB::Temple::Compiler.new
    temple = compiler.call(ast)

    assert_includes temple, [:escape, true, [:dynamic, "example"]]

    tilt = Temple::Templates::Tilt(ORB::Temple::Engine)
    output = tilt.new { input }.render

    assert_equal output, "Test 1\nTest 2\n"
  end
end
