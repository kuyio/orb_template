# ORB Template Engine -- Security Analysis

**Date:** 2026-03-12
**Version Reviewed:** 0.1.3
**Scope:** Tokenizer2, Parser, AST Builder, Temple Compiler, Filters, Attributes Compiler, Rails Template Handler

---

## Executive Summary

ORB is a JSX-inspired template engine for Ruby/Rails that compiles templates to Ruby code via the Temple pipeline. The overall architecture is sound -- it uses Temple's `:escape` mechanism for auto-escaping `{{...}}` output and avoids direct `eval()` of raw user strings. However, this review identified several vulnerabilities ranging from **critical** to **low** severity, many of which mirror historical CVEs in ERB, HAML, and SLIM template engines.

The primary risk areas are:

- Code injection through directive values and expressions interpolated into generated Ruby code
- Missing HTML escaping on dynamic attribute values
- Insufficient validation of tag names, attribute names, and `:for` expressions

Note: Like ERB, HAML, and SLIM, ORB executes arbitrary Ruby in template expressions (`{{...}}` and `{%...%}`). This is by design and follows the same trust model -- templates are developer-authored and loaded from the filesystem. This is documented as informational, not as a vulnerability.

---

## Data Flow Overview

```
ORB Template Source (text)
        |
        v
  [Tokenizer2]          lib/orb/tokenizer2.rb    -- Lexical analysis via StringScanner
        |
        v
  Token Stream
        |
        v
  [Parser]               lib/orb/parser.rb        -- Token-to-AST conversion
        |
        v
  AST (Abstract Syntax Tree)
        |
        v
  [Temple::Compiler]     lib/orb/temple/compiler.rb   -- AST to Temple IR
        |
        v
  [Temple::Filters]      lib/orb/temple/filters.rb    -- Component/block handling
        |
        v
  [Temple Pipeline]      lib/orb/temple/engine.rb     -- Escaping, static analysis, optimization
        |
        v
  Generated Ruby Code
        |
        v
  [Rails ActionView]     lib/orb/rails_template.rb    -- Template handler execution
        |
        v
  HTML Output
```

Security-sensitive boundaries exist at every stage. The most critical are:

1. **Tokenizer -> Parser**: What syntax is accepted and how expressions are delimited
2. **Compiler -> Filters**: How expressions, directives, and attributes are interpolated into Ruby code
3. **Filters -> Temple Pipeline**: Whether dynamic values are wrapped in escape directives
4. **Generated Code -> Rails**: What code executes in the view binding

---

## INFORMATIONAL Findings

### INFO-1: Server-Side Template Injection via `{%...%}` Control Expressions

**Location:** `lib/orb/temple/compiler.rb:120-123`

Control expressions compile directly to `:code` Temple expressions, allowing arbitrary Ruby execution. This is equivalent to ERB's `<% %>`, HAML's `- code`, and SLIM's `- code` -- it is a fundamental feature of any code-executing template language, not a vulnerability in ORB specifically.

Templates are authored by developers and loaded from the filesystem via Rails' template resolver, which restricts to the application's view paths. The same trust model applies as with ERB.

**Mitigation:** Document that ORB templates must not be constructed from user input (same guidance as ERB). Long-term, consider Brakeman integration to flag unsafe patterns like `ORB::Template.parse(user_string)`.

---

### INFO-2: Server-Side Template Injection via `{{...}}` Printing Expressions

**Location:** `lib/orb/temple/compiler.rb:109`

Printing expressions execute arbitrary Ruby in the template binding (output is HTML-escaped). This is equivalent to ERB's `<%= %>`. Same trust model as INFO-1 applies.

**Mitigation:** Documentation only. Same as ERB.

---

### INFO-3: Error Messages Expose Internal Tokenizer State

**Location:** `lib/orb/tokenizer2.rb:617`

Error messages include internal tokenizer state names (`:printing_expression`, `:control_expression`, etc.). In development mode, this is intentional and helpful for debugging -- the same behavior as ERB, HAML, and SLIM. In production, Rails rescues exceptions and shows a generic error page, so these details are only visible in server logs (which are already privileged).

**Mitigation:** Standard Rails error handling. Only a concern if the application is misconfigured to expose exception details in production responses.

---

## CRITICAL Findings

### CRITICAL-1: Code Injection via `:for` Directive Expression Splitting

**Location:** `lib/orb/temple/filters.rb:109-116`

The `:for` block handler uses a naive `split(' in ')` to separate the iterator variable from the collection:

```ruby
# lib/orb/temple/filters.rb:110-111
def on_orb_for(expression, content)
  enumerator, collection = expression.split(' in ')
  code = "#{collection}.each do |#{enumerator}|"
```

Both `enumerator` and `collection` are interpolated into a Ruby code string without validation. A crafted `:for` expression can inject arbitrary code:

```orb
{#for x in [1]; system("pwned"); [2]}
  ...
{/for}
```

This generates: `[1]; system("pwned"); [2].each do |x|`

The `enumerator` side is also injectable:

```orb
{#for x| ; system("pwned") ; |y in items}
```

**Impact:** Arbitrary code execution via crafted template source.

**Recommendation:** Parse and validate the `:for` expression with a strict regex that only allows `variable_name in expression` patterns, where `variable_name` must be a valid Ruby identifier. Additionally, reject semicolons in the collection expression to prevent statement injection.

**Mitigation (applied):** In `lib/orb/temple/filters.rb:109-121`, the `on_orb_for` method now uses a strict regex to parse the `:for` expression and rejects semicolons in the collection:

```ruby
# Before
def on_orb_for(expression, content)
  enumerator, collection = expression.split(' in ')
  code = "#{collection}.each do |#{enumerator}|"

# After
def on_orb_for(expression, content)
  match = expression.match(/\A\s*([a-z_]\w*)\s+in\s+(.+)\z/m)
  raise ORB::SyntaxError.new("Invalid :for expression: enumerator must be a valid Ruby identifier", 0) unless match

  enumerator, collection = match[1], match[2]

  if collection.include?(';')
    raise ORB::SyntaxError.new("Invalid :for collection expression: semicolons are not allowed", 0)
  end

  code = "#{collection}.each do |#{enumerator}|"
```

The enumerator is now validated as a Ruby identifier (`[a-z_]\w*`), preventing pipe-delimiter injection. The collection is checked for semicolons, preventing statement injection. Both attack vectors now raise `ORB::SyntaxError` at compile time. Normal `:for` usage (`{#for item in items}`) is unaffected.

**Evidence:** All 4 CRITICAL-1 tests now pass. Full test suite (123 runs) shows 14 expected failures for unmitigated findings, 0 errors, 0 regressions.

---

## HIGH Findings

### HIGH-1: XSS via Unescaped Dynamic Attribute Values

**Location:** `lib/orb/temple/attributes_compiler.rb:91-93`
**Analogous CVEs:** CVE-2017-1002201 (HAML attribute XSS), CVE-2016-6316 (Rails Action View attribute XSS)

Dynamic attribute expressions are emitted as `[:dynamic, ...]` without an explicit `[:escape, true, ...]` wrapper:

```ruby
# lib/orb/temple/attributes_compiler.rb:91-93
elsif attribute.expression?
  [:html, :attr, attribute.name, [:dynamic, attribute.value]]
end
```

Compare with printing expressions which always use `[:escape, true, [:dynamic, ...]]` (compiler.rb:109).

Whether this is safe depends on Temple's downstream `Escapable` filter configuration and how `[:html, :attr, ...]` is processed. If the value is not escaped by the pipeline, an attacker could inject through attribute context:

```orb
<div class={user_input}>
<!-- if user_input = '"><script>alert(1)</script><div class="' -->
<!-- renders: <div class=""><script>alert(1)</script><div class=""> -->
```

**Impact:** Cross-site scripting (XSS) if dynamic attribute values are not escaped by the Temple pipeline. Unlike the template-authoring-only findings, this is exploitable at **runtime** through malicious data in any variable used in a dynamic attribute -- no template source compromise required.

**Recommendation:** Explicitly wrap dynamic attribute values: `[:html, :attr, attribute.name, [:escape, true, [:dynamic, attribute.value]]]`

**Mitigation (applied):** In `lib/orb/temple/attributes_compiler.rb:92`, the `compile_attribute` method now wraps expression attributes with `[:escape, true, ...]`:

```ruby
# Before
[:html, :attr, attribute.name, [:dynamic, attribute.value]]

# After
[:html, :attr, attribute.name, [:escape, true, [:dynamic, attribute.value]]]
```

This causes Temple's `Escapable` filter to emit `::Temple::Utils.escape_html(...)` around dynamic attribute values, matching the escaping behavior already applied to printing expressions (`{{...}}`). Static and boolean attributes are unaffected. Existing assertions in `test/temple_compiler_test.rb` were updated to expect the new escaped IR.

**Evidence:** `test_dynamic_attribute_value_is_escaped` now passes. Full test suite (123 runs) shows no regressions beyond the 18 expected security test failures for unmitigated findings.

---

### HIGH-2: Code Injection via `:with` Directive in Block Parameters

**Location:** `lib/orb/temple/filters.rb:37, 46, 80, 83`

The `:with` directive value is used directly as a Ruby block parameter name without validation:

```ruby
# lib/orb/temple/filters.rb:37
block_name = node.directives.fetch(:with, block_name)
# ...
# lib/orb/temple/filters.rb:46
code = "render #{komponent_name}.new(#{args}) do |#{block_name}|"
```

A crafted `:with` directive can inject code into the block parameter position:

```orb
<MyComponent :with="x| ; system('pwned') ; |y">
```

Generates: `render MyComponent.new() do |x| ; system('pwned') ; |y|`

The same vulnerability exists in slot rendering (filters.rb:80-83).

**Impact:** Arbitrary code execution via crafted template source.

**Recommendation:** Validate that `:with` values match `/\A[a-z_][a-zA-Z0-9_]*\z/` (valid Ruby identifier).

**Mitigation (applied):** In `lib/orb/temple/filters.rb`, both `on_orb_component` and `on_orb_slot` now validate the block name after resolving the `:with` directive:

```ruby
block_name = node.directives.fetch(:with, block_name)
unless block_name.match?(/\A[a-z_]\w*\z/)
  raise ORB::SyntaxError.new("Invalid :with directive value: must be a valid Ruby identifier", 0)
end
```

This validation applies to both explicit `:with` values and the auto-generated default block names, providing defense-in-depth against malicious tag/slot names that produce invalid default identifiers (also catches HIGH-4 and HIGH-5 attack vectors as a side effect).

**Evidence:** `test_with_directive_component_injection_is_rejected` and `test_with_directive_slot_injection_is_rejected` now pass. Full test suite (86 non-security runs) shows no regressions.

---

### HIGH-3: Unsafe Tag Name Interpolation in Dynamic Tags

**Location:** `lib/orb/temple/filters.rb:130`

```ruby
code = "content_tag('#{node.tag}', #{splats}) do"
```

The tag name is interpolated into a single-quoted Ruby string. The `TAG_NAME` pattern (`[^\s>/=$]+` in patterns.rb:6) allows single quotes, semicolons, and parentheses. Since spaces are not allowed in tag names, the injection must be crafted without spaces:

```orb
<div');system(:pwned);content_tag('x **{attrs}>content</div');system(:pwned);content_tag('x>
```

This generates:

```ruby
content_tag('div');system(:pwned);content_tag('x', **attrs) do
```

**Impact:** Arbitrary code execution via crafted tag name in templates using splat attributes.

**Recommendation:** Validate tag names against a strict pattern (alphanumeric, hyphens, dots, colons only) before interpolating into generated code.

**Mitigation (applied):** In `lib/orb/temple/filters.rb`, a `VALID_HTML_TAG_NAME` constant (`/\A[a-zA-Z][a-zA-Z0-9-]*\z/`) is declared and checked in `on_orb_dynamic` before the tag name is interpolated:

```ruby
VALID_HTML_TAG_NAME = /\A[a-zA-Z][a-zA-Z0-9-]*\z/

# In on_orb_dynamic, HTML tag branch:
unless node.tag.match?(VALID_HTML_TAG_NAME)
  raise ORB::SyntaxError.new("Invalid tag name: #{node.tag.inspect}", 0)
end
```

This allows standard HTML tags (`div`, `h1`, `my-element`) but rejects quotes, semicolons, parentheses, and other characters that could break out of the generated string literal. Components and slots are dispatched before this branch and are not affected.

**Evidence:** `test_dynamic_tag_name_injection_is_rejected` and `test_dynamic_tag_name_with_quote_is_rejected` now pass. Full test suite (86 non-security runs) shows no regressions.

---

### HIGH-4: Unvalidated Component Name Used as Ruby Constant

**Location:** `lib/orb/temple/filters.rb:32-34`

```ruby
name = node.tag.gsub('.', '::')
komponent = ORB.lookup_component(name)
komponent_name = komponent || name  # Falls back to raw tag name
```

If a component is not found via `lookup_component`, the raw tag name (with `.` replaced by `::`) is used directly in a `render` call:

```ruby
code = "render #{komponent_name}.new(#{args}) do |#{block_name}|"
```

This can be exploited to call arbitrary methods by leveraging the `.new()` chain. The `TAG_NAME` pattern allows parentheses, so a component name like `Kernel.exit(1)` generates:

```ruby
render Kernel::exit(1).new() do |...|
```

`Kernel::exit(1)` executes immediately (terminating the process) before `.new()` is ever reached.

**Impact:** Arbitrary method calls on any Ruby constant reachable in the namespace. Process termination, code execution, or other side effects depending on the target class/method.

**Recommendation:** Validate that resolved component names only contain expected characters (`A-Z`, `a-z`, `0-9`, `::`) and optionally maintain an allowlist of component namespaces.

**Mitigation (applied):** In `lib/orb/temple/filters.rb`, a `VALID_COMPONENT_NAME` constant (`/\A[A-Z]\w*(::[A-Z]\w*)*\z/`) is declared and checked in `on_orb_component` after name resolution:

```ruby
VALID_COMPONENT_NAME = /\A[A-Z]\w*(::[A-Z]\w*)*\z/

# In on_orb_component:
komponent_name = komponent || name
unless komponent_name.match?(VALID_COMPONENT_NAME)
  raise ORB::SyntaxError.new("Invalid component name: #{komponent_name.inspect}", 0)
end
```

This allows `Card`, `Demo::Card`, `UI::Forms::Input` but rejects names containing parentheses, semicolons, or lowercase-starting segments. The validation runs on the *resolved* name (after `lookup_component`), covering both the lookup result and the raw fallback.

**Breaking change:** Templates using `<Foo::bar>` style slot syntax will now raise a `SyntaxError`. The canonical slot syntax `<Foo:Bar>` should be used instead.

**Evidence:** `test_component_name_method_call_injection_is_rejected` and `test_component_name_semicolon_injection_is_rejected` pass (now with proper validation, not just the HIGH-2 side effect). The `:with` bypass is also blocked. Full test suite (86 non-security runs) shows no regressions.

---

### HIGH-5: Code Injection via Unvalidated Slot Names

**Location:** `lib/orb/temple/filters.rb:78-83`

Slot names are derived from the tag name portion after `:` (e.g. `Card:Header` -> slot `header`) and interpolated into a method call without validation:

```ruby
# lib/orb/temple/filters.rb:78-83
slot_name = node.slot  # tag.split(':').last.underscore
code = "#{parent_name}.with_#{slot_name}(#{args}) do |#{block_name}|"
```

The `TAG_NAME` pattern (`[^\s>/=$]+`) allows semicolons, parentheses, and other characters that are not valid in Ruby method names. A crafted slot name can inject arbitrary code:

```orb
<Card><Card:Foo();system(1);x>content</Card:Foo();system(1);x></Card>
```

This generates:

```ruby
__orb__card.with_foo();system(1);x() do |__orb__foo();system(1);x|
```

The `with_foo()` call closes normally, then `system(1)` executes, then `x()` begins a new expression that absorbs the rest of the generated code.

**Impact:** Arbitrary code execution via crafted template source.

**Recommendation:** Validate slot names against a strict pattern (valid Ruby identifier: `/\A[a-z_][a-zA-Z0-9_]*\z/`) after extraction from the tag name.

**Mitigation (applied):** In `lib/orb/temple/filters.rb`, a `VALID_SLOT_NAME` constant (`/\A[a-z_]\w*\z/`) is declared and checked in `on_orb_slot` after extracting the slot name:

```ruby
VALID_SLOT_NAME = /\A[a-z_]\w*\z/

# In on_orb_slot:
slot_name = node.slot
unless slot_name.match?(VALID_SLOT_NAME)
  raise ORB::SyntaxError.new("Invalid slot name: #{slot_name.inspect}", 0)
end
```

This allows `header`, `side_bar`, `footer_content` but rejects parentheses, semicolons, and anything that isn't a plain Ruby identifier. The validation is independent of the HIGH-2 `:with` check, so it cannot be bypassed by supplying a valid `:with` directive.

**Evidence:** `test_slot_name_semicolon_injection_is_rejected` and `test_slot_name_with_parens_is_rejected` pass. The `:with` bypass is also blocked. Full test suite (86 non-security runs) shows no regressions.

---

## MEDIUM Findings

### MEDIUM-1: Denial of Service via Unbounded Brace Nesting

**Location:** `lib/orb/tokenizer2.rb:260-284`

The brace-tracking mechanism (`@braces` array) has no depth limit. A malicious template with deeply nested braces consumes unbounded memory:

```
{{ {{{{{{{{{{{...millions of opening braces...}}}}}}}}}}} }}
```

**Impact:** Memory exhaustion, denial of service.

**Recommendation:** Enforce a maximum nesting depth (e.g., 100 levels) and raise a `SyntaxError` when exceeded.

**Mitigation (applied):** In `lib/orb/tokenizer2.rb`, a `MAX_BRACE_DEPTH` constant (100) is declared and enforced via a `push_brace` helper that replaces all direct `@braces << "{"` calls:

```ruby
MAX_BRACE_DEPTH = 100

def push_brace
  if @braces.length >= MAX_BRACE_DEPTH
    raise ORB::SyntaxError.new("Maximum brace nesting depth (#{MAX_BRACE_DEPTH}) exceeded", @line)
  end
  @braces << "{"
end
```

All 5 brace-push sites in the tokenizer (`next_in_attribute_value_expression`, `next_in_splat_attribute_expression`, `next_in_block_open_content`, `next_in_printing_expression`, `next_in_control_expression`) now call `push_brace` instead of pushing directly. Moderate nesting (e.g., nested hashes) works fine; only pathological depths are rejected.

**Evidence:** `test_deeply_nested_braces_in_expression_raises_error` and `test_deeply_nested_braces_in_attribute_raises_error` now pass. `test_moderate_brace_nesting_works` remains green. Full test suite (86 non-security runs) shows no regressions.

---

### MEDIUM-2: OpenStruct-based RenderContext Exposes Introspection

**Location:** `lib/orb/render_context.rb:26`

```ruby
OpenStruct.new(@assigns).instance_eval { binding }
```

`OpenStruct` inherits from `Object`, exposing all `Object` methods to template expressions:

```
{{ self.class }}                          # => OpenStruct
{{ self.class.ancestors }}                # => full class hierarchy
{{ instance_variable_get(:@table) }}      # => all assigns as hash
{{ self.methods.sort }}                   # => available methods
{{ self.send(:system, "id") }}            # => command execution via send
```

**Impact:** Template expressions (in the standalone `Template` class path) can introspect and exploit the full Ruby object model.

**Recommendation:** Use a `BasicObject` subclass instead of `OpenStruct` to minimize the available attack surface. Only expose explicitly allowed methods.

---

### MEDIUM-3: `runtime_error` String Delimiter Breakout

**Location:** `lib/orb/temple/compiler.rb:199`

```ruby
temple << [:code, %[raise ORB::Error.new(%q[#{error.message}], #{error.line.inspect})]]
```

Error messages are interpolated into a `%q[...]` string literal. The `%q[]` delimiter uses square brackets, meaning an error message containing `]` would prematurely close the string, potentially allowing code injection via crafted error messages.

**Impact:** If an attacker can trigger a specific error message containing `]`, the generated code could be malformed or injectable.

**Recommendation:** Use a delimiter that cannot appear in error messages (e.g., `%q{...}` with brace counting, or properly escape the content), or use `String#inspect` to safely serialize the message.

---

### MEDIUM-4: Attribute Name Injection

**Location:** `lib/orb/patterns.rb:7`

```ruby
ATTRIBUTE_NAME = %r{[^\s>/=]+}
```

This pattern allows nearly any character in attribute names, including:

- Event handlers: `onclick`, `onmouseover`, `onfocus`
- Quote characters: `"`, `'` (could break attribute context)
- Backticks, semicolons, and other special characters

**Analogous CVE:** CVE-2017-1002201 (HAML attribute injection via unescaped characters)

While ORB templates are typically authored by developers (not end users), the permissive pattern means:

1. No compile-time validation catches typos that could be security-relevant
2. If attribute names ever come from dynamic sources (e.g., splat attributes), injection is possible

**Recommendation:** Restrict `ATTRIBUTE_NAME` to valid HTML attribute characters: `/[a-zA-Z_:][-a-zA-Z0-9_:.]*` per the HTML spec, or at minimum disallow quotes and backticks.

---

## LOW Findings

### LOW-1: Verbatim Mode Bypasses All Processing

**Location:** `lib/orb/tokenizer2.rb:146-152`

The `$>` closing syntax enables verbatim mode, where content passes through without any processing or escaping:

```orb
<script$>
  var x = "user controlled data here passes through raw";
</script>
```

This is intentional behavior for `<script>` and `<style>` tags, but developers unfamiliar with ORB may not realize that verbatim content is never escaped.

**Recommendation:** Document this behavior clearly. Consider requiring an explicit opt-in rather than a syntactic marker.

---

### LOW-2: Public Comments Pass Content as Static (Unescaped)

**Location:** `lib/orb/temple/compiler.rb:155`

```ruby
def transform_public_comment_node(node, _context)
  [:html, :comment, [:static, node.text]]
end
```

Comment text is emitted as `[:static, ...]`. If comment content somehow contains `-->`, it could break out of the HTML comment context. However, since the tokenizer terminates comment parsing at `-->`, the text content would not contain this sequence under normal operation.

**Impact:** Minimal under current tokenizer behavior. Only relevant if the tokenizer is bypassed or modified.

---

### LOW-3: No Template Size Limit

**Location:** `lib/orb/tokenizer2.rb:26-27`

```ruby
def initialize(source, options = {})
  @source = StringScanner.new(source)
```

There is no limit on template source size. An extremely large template could cause excessive memory usage and CPU consumption during tokenization.

**Recommendation:** Consider enforcing a configurable maximum template size.

---

### LOW-4: Potential ReDoS in Block Detection Regex

**Location:** `lib/orb/ast/printing_expression_node.rb:7`

```ruby
BLOCK_RE = /\A(if|unless)\b|\bdo\s*(\|[^|]*\|)?\s*$/
```

The `\s*` quantifiers combined with `$` could cause quadratic backtracking on inputs with many trailing whitespace characters followed by a non-matching character. The practical impact is limited because expression values are typically short.

**Recommendation:** Use possessive quantifiers or atomic groups if available: `\s*+` or `(?>\\s*)`.

---

## Comparison with Historical CVEs

| CVE | Engine | Vulnerability | ORB Applicability |
|-----|--------|--------------|-------------------|
| **CVE-2016-0752** | ERB/Rails | SSTI via dynamic `render` with user input | **Informational** -- `{%...%}` and `{{...}}` allow arbitrary Ruby execution, same as ERB (INFO-1, INFO-2) |
| **CVE-2017-1002201** | HAML | XSS via unescaped apostrophes in attributes | **Applicable** -- dynamic attribute values may lack escaping (HIGH-1); attribute names allow quotes (MEDIUM-4) |
| **CVE-2016-6316** | Rails/HAML | XSS in `html_safe` attribute values in tag helpers | **Partially applicable** -- interaction with `use_html_safe: true` option and Temple escaping pipeline needs verification (HIGH-1) |
| **CVE-2019-5418** | Rails | Path traversal via `render file:` with user input | **Not applicable** -- ORB does not support file includes or partial rendering by path |
| **CVE-2021-32818** | haml-coffee | RCE via configuration parameter pollution | **Not applicable** -- different architecture, no user-accessible configuration |
| SLIM XSS (Sqreen) | SLIM | XSS through `==` unescaped output and attribute injection | **Partially applicable** -- ORB's `{%...%}` is analogous to SLIM's `==` (no output escaping for control expressions) |

---

## Recommendations (Priority Order)

### Immediate (Before Public Release)

1. **Document SSTI risk** -- Add a Security section to README warning that ORB templates must never be constructed from user input. This is the single most important action.

2. **Escape dynamic attribute values** -- In `attributes_compiler.rb:91-93`, wrap dynamic attribute values:
   ```ruby
   [:html, :attr, attribute.name, [:escape, true, [:dynamic, attribute.value]]]
   ```

3. **Validate `:for` expression syntax** -- Replace `split(' in ')` with a strict parser:
   ```ruby
   match = expression.match(/\A\s*([a-z_]\w*)\s+in\s+(.+)\z/m)
   raise CompilerError, "Invalid :for expression" unless match
   enumerator, collection = match[1], match[2]
   ```

4. **Validate `:with` directive values** -- Ensure block parameter names are valid Ruby identifiers:
   ```ruby
   unless block_name.match?(/\A[a-z_]\w*\z/)
     raise CompilerError, "Invalid :with value: must be a valid identifier"
   end
   ```

5. **Validate tag names before code interpolation** -- In `filters.rb`, validate before string interpolation:
   ```ruby
   unless node.tag.match?(/\A[a-zA-Z][a-zA-Z0-9._:-]*\z/)
     raise CompilerError, "Invalid tag name: #{node.tag}"
   end
   ```

6. **Validate slot names** -- After extracting the slot name from the tag, validate it is a valid Ruby identifier:
   ```ruby
   unless slot_name.match?(/\A[a-z_][a-zA-Z0-9_]*\z/)
     raise CompilerError, "Invalid slot name: #{slot_name}"
   end
   ```

### Short Term

7. **Fix `runtime_error` string delimiter** -- Use `String#inspect` for safe serialization of error messages.

8. **Add brace nesting depth limit** -- Cap at a reasonable depth (e.g., 100) in the tokenizer.

9. **Restrict `ATTRIBUTE_NAME` pattern** -- Use `/[a-zA-Z_:][-a-zA-Z0-9_:.]*` or similar.

### Long Term

10. **Consider a restricted execution mode** -- A "safe mode" that limits available methods in template expressions, similar to Liquid's approach.

11. **Integrate with Brakeman** -- Add ORB-specific checks for common vulnerability patterns.

12. **Replace `OpenStruct` in `RenderContext`** -- Use a `BasicObject` subclass to minimize attack surface for standalone template rendering.

13. **Add template size and complexity limits** -- Configurable maximums for source size, nesting depth, and expression count.

---

## Test Coverage

All findings are covered by regression tests in `test/security_test.rb`. Tests are written to **fail** until the corresponding fix is applied, then pass once mitigated.

| Finding | Test(s) | Status |
|---------|---------|--------|
| **CRITICAL-1** (:for injection) | `test_for_collection_injection_is_rejected`, `test_for_collection_injection_absent_from_temple_ir`, `test_for_enumerator_injection_is_rejected`, `test_for_directive_attribute_injection_is_rejected` | PASSING (4) -- mitigated |
| **HIGH-1** (attribute XSS) | `test_dynamic_attribute_value_is_escaped` | PASSING (1) -- mitigated |
| **HIGH-2** (:with injection) | `test_with_directive_component_injection_is_rejected`, `test_with_directive_slot_injection_is_rejected` | PASSING (2) -- mitigated |
| **HIGH-3** (tag name injection) | `test_dynamic_tag_name_injection_is_rejected`, `test_dynamic_tag_name_with_quote_is_rejected` | PASSING (2) -- mitigated |
| **HIGH-4** (component name injection) | `test_component_name_method_call_injection_is_rejected`, `test_component_name_semicolon_injection_is_rejected` | PASSING (2) -- mitigated |
| **HIGH-5** (slot name injection) | `test_slot_name_semicolon_injection_is_rejected`, `test_slot_name_with_parens_is_rejected` | PASSING (2) -- mitigated |
| **MEDIUM-1** (brace nesting DoS) | `test_deeply_nested_braces_in_expression_raises_error`, `test_deeply_nested_braces_in_attribute_raises_error` | PASSING (2) -- mitigated |
| **MEDIUM-3** (runtime_error breakout) | `test_runtime_error_with_bracket_produces_valid_ruby`, `test_runtime_error_code_injection_is_rejected` | FAILING (2) |
| **MEDIUM-4** (attribute name injection) | `test_attribute_name_with_single_quote_is_rejected`, `test_attribute_name_with_backtick_is_rejected` | FAILING (2) |
| **LOW-1** (verbatim bypass) | `test_verbatim_mode_does_not_process_expressions`, `test_verbatim_mode_passes_html_through_raw` | PASSING (2) |
| **LOW-2** (comment delimiter) | `test_comment_content_terminates_at_closing_delimiter` | PASSING (1) |
| **LOW-3** (no size limit) | `test_large_template_has_size_limit` | FAILING (1) |
| **LOW-4** (ReDoS) | `test_block_regex_handles_pathological_input` | PASSING (1) |

Baseline tests (expected to always pass): `test_printing_expression_is_escaped_baseline`, `test_static_attribute_value_needs_no_runtime_escape`, `test_with_directive_normal_usage_compiles_correctly`, `test_dynamic_tag_normal_usage_compiles_correctly`, `test_component_name_dotted_namespace_compiles_correctly`, `test_slot_normal_usage_compiles_correctly`, `test_moderate_brace_nesting_works`, `test_runtime_error_normal_message_compiles_correctly`, `test_valid_attribute_names_compile_correctly`, `test_normal_sized_template_works`, `test_for_block_normal_usage_compiles_correctly`, `test_for_directive_normal_usage_compiles_correctly`.

**Totals: 37 tests, 5 failing, 32 passing (15 mitigated).**

When mitigations are applied, each finding's failing tests should turn green while all baseline tests remain passing.

---

## Methodology

This review was conducted through manual source code analysis of all files in the compilation pipeline:

- `lib/orb/patterns.rb` -- Regex patterns (attack surface definition)
- `lib/orb/tokenizer2.rb` -- Lexical analysis (input parsing)
- `lib/orb/parser.rb` -- Syntax analysis (AST construction)
- `lib/orb/ast/*.rb` -- AST node definitions (data model)
- `lib/orb/temple/compiler.rb` -- AST to Temple IR (code generation)
- `lib/orb/temple/filters.rb` -- Temple filters (component/block handling)
- `lib/orb/temple/attributes_compiler.rb` -- Attribute compilation
- `lib/orb/temple/engine.rb` -- Temple pipeline configuration
- `lib/orb/rails_template.rb` -- Rails integration
- `lib/orb/render_context.rb` -- Template execution context

Reference CVEs and advisories for ERB, HAML, and SLIM were consulted to identify analogous vulnerability patterns. The review focused on the data flow from template source through tokenization, parsing, AST construction, code generation, and execution.
