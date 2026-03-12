# frozen_string_literal: true

require_relative "test_helper"

class SecurityTest < Minitest::Test
  # ---------------------------------------------------------------------------
  # CRITICAL-1: Code Injection via :for Directive Expression Splitting
  #
  # The :for filter splits on " in " and interpolates both sides into a Ruby
  # code string without validation. This allows injecting arbitrary Ruby code
  # through the collection side or the enumerator side of the expression.
  #
  # See: security-analysis.md, CRITICAL-1
  # ---------------------------------------------------------------------------

  # Helper: run the full Temple pipeline and return the generated Ruby code
  def compile(template)
    engine = ORB::Temple::Engine.new(
      generator: ::Temple::Generators::StringBuffer,
      use_html_safe: false,
      streaming: false,
      disable_capture: false
    )
    engine.call(template)
  end

  # Helper: run the Temple pipeline up to the Filters stage and return
  # the Temple IR so we can inspect what code expressions are generated
  def compile_to_temple(template)
    parser = ORB::Temple::Parser.new
    ast = parser.call(template)
    compiler = ORB::Temple::Compiler.new
    temple = compiler.call(ast)
    filters = ORB::Temple::Filters.new
    filters.call(temple)
  end

  # --- Collection-side injection ---

  # Injecting code via the collection side of {#for} must raise a SyntaxError
  # because semicolons are not allowed in the collection expression.
  def test_for_collection_injection_is_rejected
    malicious_template = '{#for item in []; system("id"); [].each}content{/for}'

    assert_raises(ORB::SyntaxError) do
      compile(malicious_template)
    end
  end

  # The Temple IR must not contain the injected code in any :code node.
  def test_for_collection_injection_absent_from_temple_ir
    malicious_template = '{#for x in items; malicious_call; arr}content{/for}'

    assert_raises(ORB::SyntaxError) do
      compile_to_temple(malicious_template)
    end
  end

  # --- Enumerator-side injection ---

  # Injecting code via the enumerator (variable name) side of {#for}
  # must raise a SyntaxError because the enumerator is not a valid identifier.
  def test_for_enumerator_injection_is_rejected
    malicious_template = '{#for x| ; malicious_call ; |y in items}content{/for}'

    assert_raises(ORB::SyntaxError) do
      compile(malicious_template)
    end
  end

  # --- :for directive on tags ---

  # The same injection via :for as a tag directive attribute must be rejected.
  def test_for_directive_attribute_injection_is_rejected
    malicious_template = '<div :for="item in []; system(:pwned); []">content</div>'

    assert_raises(ORB::SyntaxError) do
      compile(malicious_template)
    end
  end

  # ---------------------------------------------------------------------------
  # HIGH-1: XSS via Unescaped Dynamic Attribute Values
  #
  # Dynamic attribute expressions (e.g. class={expr}) are compiled to Temple
  # [:dynamic, ...] nodes WITHOUT an [:escape, true, ...] wrapper, while
  # printing expressions (e.g. {{expr}}) ARE escaped. This means dynamic
  # attribute values are interpolated into HTML without HTML-escaping,
  # allowing XSS if the expression contains user-controlled data.
  #
  # See: security-analysis.md, HIGH-1
  # ---------------------------------------------------------------------------

  # Dynamic attribute values must be HTML-escaped in the generated code,
  # just like printing expressions are.
  def test_dynamic_attribute_value_is_escaped
    template = '<div class={user_input}>text</div>'

    generated_code = compile(template)

    assert_includes generated_code, "escape_html",
      "Dynamic attribute values must be HTML-escaped in generated code.\n" \
      "Generated code was: #{generated_code}"
  end

  # Printing expressions ARE escaped -- this baseline confirms the mechanism works.
  def test_printing_expression_is_escaped_baseline
    template = '<div>{{user_input}}</div>'

    generated_code = compile(template)

    assert_includes generated_code, "escape_html",
      "Printing expressions should be HTML-escaped (baseline)"
  end

  # Static attribute values don't need runtime escaping (they are trusted
  # developer-authored strings), so this just confirms the distinction.
  def test_static_attribute_value_needs_no_runtime_escape
    template = '<div class="safe">text</div>'

    generated_code = compile(template)

    refute_includes generated_code, "escape_html",
      "Static attributes should not need runtime escape_html calls"
  end

  # ---------------------------------------------------------------------------
  # HIGH-2: Code Injection via :with Directive in Block Parameters
  #
  # The :with directive value is used directly as a Ruby block parameter name
  # without validation. Since block params are delimited by pipes (|...|),
  # an attacker who can author a template can inject arbitrary code by
  # closing and reopening the pipe delimiters.
  #
  # Note: like CRITICAL-1, this requires crafting the template source itself.
  #
  # See: security-analysis.md, HIGH-2
  # ---------------------------------------------------------------------------

  # Injecting code via :with on a component must raise a SyntaxError.
  def test_with_directive_component_injection_is_rejected
    malicious_template = '<Card :with="x| ; system(:pwned) ; |y">content</Card>'

    assert_raises(ORB::SyntaxError) do
      compile(malicious_template)
    end
  end

  # Injecting code via :with on a component slot must raise a SyntaxError.
  def test_with_directive_slot_injection_is_rejected
    malicious_template = '<Card><Card:Header :with="x| ; system(:pwned) ; |y">content</Card:Header></Card>'

    assert_raises(ORB::SyntaxError) do
      compile(malicious_template)
    end
  end

  # Normal :with usage should still work.
  def test_with_directive_normal_usage_compiles_correctly
    template = '<Card :with="my_card">content</Card>'

    generated_code = compile(template)

    assert_includes generated_code, "do |my_card|",
      "Normal :with directive should compile to a block parameter"
    refute_includes generated_code, "system",
      "Normal :with should not contain any system calls"
  end

  # ---------------------------------------------------------------------------
  # HIGH-3: Unsafe Tag Name Interpolation in Dynamic Tags
  #
  # When a tag has splat attributes, it is compiled via content_tag where the
  # tag name is interpolated into a single-quoted Ruby string:
  #
  #   content_tag('#{node.tag}', #{splats}) do
  #
  # The TAG_NAME pattern ([^\s>/=$]+) allows single quotes and semicolons,
  # so a crafted tag name can break out of the string and inject arbitrary
  # Ruby code -- without needing spaces.
  #
  # Note: requires crafting the template source itself.
  #
  # See: security-analysis.md, HIGH-3
  # ---------------------------------------------------------------------------

  # A tag name containing quotes and semicolons must raise a SyntaxError.
  # Payload: div');system(:pwned);content_tag('x
  # This would generate: content_tag('div');system(:pwned);content_tag('x', ...) do
  def test_dynamic_tag_name_injection_is_rejected
    malicious_open = "<div');system(:pwned);content_tag('x **{attrs}>content"
    malicious_close = "</div');system(:pwned);content_tag('x>"

    assert_raises(ORB::SyntaxError) do
      compile(malicious_open + malicious_close)
    end
  end

  # A tag name containing just a single quote must raise a SyntaxError.
  def test_dynamic_tag_name_with_quote_is_rejected
    malicious_open = "<div' **{attrs}>content"
    malicious_close = "</div'>"

    assert_raises(ORB::SyntaxError) do
      compile(malicious_open + malicious_close)
    end
  end

  # Normal dynamic HTML tag with splat should still work.
  def test_dynamic_tag_normal_usage_compiles_correctly
    template = '<div **{attrs}>content</div>'

    generated_code = compile(template)

    assert_includes generated_code, "content_tag('div'",
      "Normal dynamic tag should compile to a content_tag call"
    refute_includes generated_code, "system",
      "Normal dynamic tag should not contain any system calls"
  end

  # ---------------------------------------------------------------------------
  # HIGH-4: Unvalidated Component Name Used as Ruby Constant
  #
  # Component tag names are transformed via gsub('.', '::') and interpolated
  # directly into a `render` call. The TAG_NAME pattern allows parentheses,
  # semicolons, and other characters that are not valid in Ruby constants,
  # enabling two attack vectors:
  #
  # 1. Method call injection: <Kernel.exit(1)> generates Kernel::exit(1).new()
  #    which calls exit(1) before .new() is reached.
  #
  # 2. Statement injection: semicolons in the tag name inject arbitrary
  #    statements into the generated code.
  #
  # Note: requires crafting the template source itself.
  #
  # See: security-analysis.md, HIGH-4
  # ---------------------------------------------------------------------------

  # A component name like Kernel.exit(1) must not compile to a method call.
  # Without validation, this generates: render Kernel::exit(1).new()
  # which would terminate the process before .new() is evaluated.
  def test_component_name_method_call_injection_is_rejected
    malicious_template = '<Kernel.exit(1)>content</Kernel.exit(1)>'

    assert_raises(ORB::SyntaxError) do
      compile(malicious_template)
    end
  end

  # A component name with semicolons must not inject additional statements.
  def test_component_name_semicolon_injection_is_rejected
    malicious_template = '<Foo;system(:pwned);Bar>content</Foo;system(:pwned);Bar>'

    assert_raises(ORB::SyntaxError) do
      compile(malicious_template)
    end
  end

  # A dotted component name mapping to a real namespace should still work.
  def test_component_name_dotted_namespace_compiles_correctly
    template = '<Card>content</Card>'

    generated_code = compile(template)

    assert_includes generated_code, "render Demo::Card.new()",
      "Normal component should compile to a render call with namespace lookup"
    refute_includes generated_code, "system",
      "Normal component should not contain any system calls"
  end

  # ---------------------------------------------------------------------------
  # MEDIUM-1: Denial of Service via Unbounded Brace Nesting
  #
  # The tokenizer tracks nested braces in an unbounded array (@braces).
  # A malicious template with deeply nested braces consumes memory
  # proportional to the nesting depth with no enforced limit.
  #
  # The fix should enforce a maximum nesting depth and raise a SyntaxError
  # when exceeded.
  #
  # See: security-analysis.md, MEDIUM-1
  # ---------------------------------------------------------------------------

  # Deeply nested braces in a printing expression should raise a SyntaxError
  # rather than consuming unbounded memory.
  def test_deeply_nested_braces_in_expression_raises_error
    depth = 1000
    source = "{{ " + ("{" * depth) + ("}" * depth) + " }}"

    assert_raises(ORB::SyntaxError) do
      ORB::Tokenizer2.new(source).tokenize
    end
  end

  # Deeply nested braces in an attribute expression should also be limited.
  def test_deeply_nested_braces_in_attribute_raises_error
    depth = 1000
    source = "<div class={" + ("{" * depth) + ("}" * depth) + "}>text</div>"

    assert_raises(ORB::SyntaxError) do
      ORB::Tokenizer2.new(source).tokenize
    end
  end

  # Reasonable nesting depth should still work fine.
  def test_moderate_brace_nesting_works
    # Something like {{ {key: {nested: value}} }} -- a few levels deep
    source = "{{ {a: {b: {c: 1}}} }}"

    tokens = ORB::Tokenizer2.new(source).tokenize

    assert tokens.any? { |t| t.type == :printing_expression },
      "Moderate brace nesting should tokenize successfully"
  end

  # ---------------------------------------------------------------------------
  # MEDIUM-3: `runtime_error` String Delimiter Breakout
  #
  # The Compiler#runtime_error method generates code using %q[] delimiters:
  #
  #   raise ORB::Error.new(%q[#{error.message}], #{error.line.inspect})
  #
  # If an error message contains ']', it prematurely closes the %q[] string.
  # With a crafted message, this can produce valid Ruby that injects code:
  #
  #   raise ORB::Error.new(%q[x]); system(:pwned); raise(%q[y], 5)
  #
  # See: security-analysis.md, MEDIUM-3
  # ---------------------------------------------------------------------------

  # An error message containing ] must not break the generated code or
  # allow code injection via the %q[] delimiter.
  def test_runtime_error_with_bracket_produces_valid_ruby
    compiler = ORB::Temple::Compiler.new
    error = ORB::SyntaxError.new("Unexpected ] bracket", 1)

    temple = compiler.call(error)

    code_nodes = extract_code_nodes(temple)
    code_strings = code_nodes.map { |n| n[1] }

    # Every generated :code node must be valid Ruby
    code_strings.each do |code|
      result = Prism.parse(code)
      assert result.success?,
        "runtime_error generated invalid Ruby from message containing ']'.\n" \
        "Generated code: #{code}\n" \
        "Parse errors: #{result.errors.map(&:message).join('; ')}"
    end
  end

  # A crafted error message must not inject executable code between the
  # raise statements.
  def test_runtime_error_code_injection_is_rejected
    compiler = ORB::Temple::Compiler.new

    # This message is crafted to close %q[], inject system(), then reopen
    # a valid %q[] to consume the trailing ], line) portion.
    error = ORB::Error.new("x]); system(:pwned); raise(%q[y", 5)

    temple = compiler.call(error)

    code_nodes = extract_code_nodes(temple)
    code_strings = code_nodes.map { |n| n[1] }

    injected = code_strings.find { |s| s.include?("system(:pwned)") }
    refute injected,
      "Crafted error message must not inject code via %q[] breakout.\n" \
      "Generated code: #{code_strings.inspect}"
  end

  # Normal error messages without special characters should work fine.
  def test_runtime_error_normal_message_compiles_correctly
    compiler = ORB::Temple::Compiler.new
    error = ORB::SyntaxError.new("Unexpected token at line 1", 1)

    temple = compiler.call(error)

    code_nodes = extract_code_nodes(temple)
    code_strings = code_nodes.map { |n| n[1] }

    raise_code = code_strings.find { |s| s.include?("raise") }
    assert raise_code, "runtime_error should generate a raise statement"

    result = Prism.parse(raise_code)
    assert result.success?,
      "runtime_error should generate valid Ruby for normal error messages"
  end

  # ---------------------------------------------------------------------------
  # MEDIUM-4: Attribute Name Injection
  #
  # The ATTRIBUTE_NAME pattern ([^\s>/=]+) allows nearly any character
  # including quotes, backticks, and angle brackets. This can produce
  # malformed HTML output that browsers may interpret in unexpected ways.
  #
  # The HTML spec restricts attribute names to: [a-zA-Z_:][-a-zA-Z0-9_:.]*
  #
  # See: security-analysis.md, MEDIUM-4
  # ---------------------------------------------------------------------------

  # Attribute names containing double quotes can break out of the HTML tag
  # context, potentially allowing attribute injection.
  def test_attribute_name_with_double_quote_is_rejected
    template = '<div x"onclick="alert(1)" y="z">text</div>'

    # Should either raise a SyntaxError during tokenization or produce
    # output that does not contain the raw double quote in the attr name
    begin
      generated_code = compile(template)
      refute_includes generated_code, 'x"onclick',
        "Attribute name containing double quote must not pass through to output.\n" \
        "Generated code was: #{generated_code}"
    rescue ORB::SyntaxError
      pass # Raising a SyntaxError is also acceptable
    end
  end

  # Attribute names containing single quotes should be rejected.
  def test_attribute_name_with_single_quote_is_rejected
    template = "<div x'onclick='alert(1)' y='z'>text</div>"

    begin
      generated_code = compile(template)
      refute_includes generated_code, "x'onclick",
        "Attribute name containing single quote must not pass through to output.\n" \
        "Generated code was: #{generated_code}"
    rescue ORB::SyntaxError
      pass
    end
  end

  # Attribute names containing backticks should be rejected.
  def test_attribute_name_with_backtick_is_rejected
    template = "<div x\x60y=\"val\">text</div>"

    begin
      generated_code = compile(template)
      refute_includes generated_code, "x`y",
        "Attribute name containing backtick must not pass through to output.\n" \
        "Generated code was: #{generated_code}"
    rescue ORB::SyntaxError
      pass
    end
  end

  # Valid HTML attribute names should still work.
  def test_valid_attribute_names_compile_correctly
    template = '<div class="a" data-value="b" aria-label="c" id="d">text</div>'

    generated_code = compile(template)

    assert_includes generated_code, "class",
      "Standard attribute names should compile correctly"
    assert_includes generated_code, "data-value",
      "Dashed attribute names should compile correctly"
    assert_includes generated_code, "aria-label",
      "ARIA attribute names should compile correctly"
  end

  # ---------------------------------------------------------------------------
  # HIGH-5: Code Injection via Unvalidated Slot Names
  #
  # Slot names are derived from the tag name portion after ':' (e.g.
  # Card:Header -> slot name "header") and interpolated into a method call:
  #
  #   #{parent_name}.with_#{slot_name}(#{args}) do |#{block_name}|
  #
  # The TAG_NAME pattern allows semicolons and parentheses, so a crafted
  # slot name can inject arbitrary code:
  #
  #   <Card:Foo();system(1);x> generates:
  #   __orb__card.with_foo();system(1);x() do |...|
  #
  # Note: requires crafting the template source itself.
  #
  # See: security-analysis.md
  # ---------------------------------------------------------------------------

  # A slot name containing semicolons and parens must not inject code.
  def test_slot_name_semicolon_injection_is_rejected
    malicious_template = "<Card><Card:Foo();system(1);x>content</Card:Foo();system(1);x></Card>"

    assert_raises(ORB::SyntaxError) do
      compile(malicious_template)
    end
  end

  # A slot name with parentheses must not produce double-parens or method calls.
  def test_slot_name_with_parens_is_rejected
    malicious_template = "<Card><Card:Foo()>content</Card:Foo()></Card>"

    assert_raises(ORB::SyntaxError) do
      compile(malicious_template)
    end
  end

  # Normal slot usage should still work.
  def test_slot_normal_usage_compiles_correctly
    template = "<Card><Card:Header>content</Card:Header></Card>"

    generated_code = compile(template)

    assert_includes generated_code, "with_header()",
      "Normal slot should compile to a with_[name] method call"
    refute_includes generated_code, "system",
      "Normal slot should not contain any system calls"
  end

  # ---------------------------------------------------------------------------
  # LOW-1: Verbatim Mode Bypasses All Processing
  #
  # The $> closing syntax enables verbatim mode where content passes through
  # without any tokenization or escaping. ORB expressions like {{...}} inside
  # verbatim tags are treated as literal text, not evaluated.
  #
  # This is by design for <script> and <style> tags, but could be a footgun
  # if developers place user-controlled data inside verbatim blocks.
  #
  # See: security-analysis.md, LOW-1
  # ---------------------------------------------------------------------------

  # Verbatim mode must pass content through without processing ORB expressions.
  def test_verbatim_mode_does_not_process_expressions
    template = "<script$>\nvar x = \"{{ should_not_eval }}\";\n</script$>"

    generated_code = compile(template)

    # The {{ }} should appear as literal text, not as an escape_html call
    refute_includes generated_code, "escape_html",
      "Verbatim content must not process ORB expressions"
    assert_includes generated_code, "{{ should_not_eval }}",
      "Verbatim content should preserve ORB syntax as literal text"
  end

  # Verbatim mode must pass HTML tags through without escaping.
  def test_verbatim_mode_passes_html_through_raw
    template = "<script$>\nvar x = \"<b>bold</b>\";\n</script$>"

    generated_code = compile(template)

    assert_includes generated_code, "<b>bold</b>",
      "Verbatim content should preserve HTML tags as literal text"
  end

  # ---------------------------------------------------------------------------
  # LOW-2: Public Comments Pass Content as Static (Unescaped)
  #
  # Comment text is emitted as [:static, ...] which is not HTML-escaped.
  # The tokenizer terminates comment parsing at -->, so comment content
  # cannot normally contain --> to break out. This test verifies that.
  #
  # See: security-analysis.md, LOW-2
  # ---------------------------------------------------------------------------

  # The tokenizer must terminate comment content at --> so that the comment
  # body cannot contain the closing delimiter.
  def test_comment_content_terminates_at_closing_delimiter
    template = "<!-- before --> breakout <!-- after -->"

    # Check the Temple IR to verify comment boundaries are correct
    temple = compile_to_temple(template)

    # Flatten to find all :static nodes inside :comment tuples vs plain :static
    # The IR should be: [:multi, [:html, :comment, [:static, " before "]], [:static, " breakout "], [:html, :comment, [:static, " after "]]]
    comment_nodes = extract_html_comment_nodes(temple)
    comment_texts = comment_nodes.map { |n| n[2][1] }

    # Each comment should only contain its own content, not text from outside
    comment_texts.each do |text|
      refute_includes text, "breakout",
        "Comment content must terminate at --> and not consume subsequent text.\n" \
        "Comment texts were: #{comment_texts.inspect}"
    end
  end

  # ---------------------------------------------------------------------------
  # LOW-3: No Template Size Limit
  #
  # There is no limit on template source size. An extremely large template
  # can cause excessive CPU and memory consumption during tokenization.
  #
  # See: security-analysis.md, LOW-3
  # ---------------------------------------------------------------------------

  # A very large template should either be rejected or complete within a
  # reasonable time bound. This test documents the lack of a size limit.
  def test_large_template_has_size_limit
    # 1MB of text -- should either be rejected or tokenize quickly
    large_source = "x" * 1_000_000

    # Currently there is no size limit, so this will succeed.
    # When a limit is added, this should raise an error.
    assert_raises(ORB::SyntaxError) do
      ORB::Tokenizer2.new(large_source).tokenize
    end
  end

  # Normal-sized templates should work fine.
  def test_normal_sized_template_works
    template = "<div>Hello, {{name}}!</div>" * 100

    tokens = ORB::Tokenizer2.new(template).tokenize

    assert tokens.length > 0, "Normal-sized template should tokenize successfully"
  end

  # ---------------------------------------------------------------------------
  # LOW-4: Potential ReDoS in Block Detection Regex
  #
  # The BLOCK_RE regex uses \s* quantifiers that could theoretically cause
  # backtracking. In practice Ruby's regex engine handles this linearly,
  # but the test documents the expected performance boundary.
  #
  # See: security-analysis.md, LOW-4
  # ---------------------------------------------------------------------------

  # The block detection regex should handle pathological input without
  # excessive backtracking (complete in under 1 second).
  def test_block_regex_handles_pathological_input
    re = ORB::AST::PrintingExpressionNode::BLOCK_RE

    # "do" followed by 50k spaces then a non-matching character
    pathological_input = "do " + (" " * 50_000) + "!"

    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    pathological_input =~ re
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

    assert elapsed < 1.0,
      "BLOCK_RE took #{elapsed.round(4)}s on pathological input (expected < 1s)"
  end

  # --- Baseline: normal :for should still work ---

  def test_for_block_normal_usage_compiles_correctly
    template = '{#for item in items}{{item}}{/for}'

    generated_code = compile(template)

    assert_includes generated_code, "items.each do |item|",
      "Expected normal :for to compile to a standard .each iterator"
    refute_includes generated_code, "system",
      "Normal :for should not contain any system calls"
  end

  def test_for_directive_normal_usage_compiles_correctly
    template = '<li :for="item in @items">text</li>'

    generated_code = compile(template)

    assert_includes generated_code, "@items.each do |item|",
      "Expected normal :for directive to compile to a standard .each iterator"
  end

  private

  # Recursively extract all [:code, "..."] nodes from a Temple expression tree
  def extract_code_nodes(temple)
    return [] unless temple.is_a?(Array)
    return [temple] if temple[0] == :code

    temple.flat_map { |child| extract_code_nodes(child) }
  end

  # Recursively extract all [:html, :comment, ...] nodes from a Temple expression tree
  def extract_html_comment_nodes(temple)
    return [] unless temple.is_a?(Array)
    return [temple] if temple[0] == :html && temple[1] == :comment

    temple.flat_map { |child| extract_html_comment_nodes(child) }
  end
end
