# Proposal: `:unwrap` Directive for Orb Templates

## Problem

When a component should conditionally wrap its children, Orb forces you to duplicate the entire child markup:

```html
<Tooltip
  :if="{@is_last_method}"
  description="This is the only active login method."
>
  <Toggle>
    <Toggle:option
      label="On"
      to="{path(enabled:"
      true)}
      active="{@enabled}"
      method="patch"
      tone="success"
    />
    <Toggle:option
      label="Off"
      to="{path(enabled:"
      false)}
      active="{!@enabled}"
      method="patch"
    />
  </Toggle>
</Tooltip>
{#if !@is_last_method}
<Toggle>
  <Toggle:option
    label="On"
    to="{path(enabled:"
    true)}
    active="{@enabled}"
    method="patch"
    tone="success"
  />
  <Toggle:option
    label="Off"
    to="{path(enabled:"
    false)}
    active="{!@enabled}"
    method="patch"
  />
</Toggle>
{/if}
```

`:if` controls whether an element **and its children** render. There is no way to say "skip the wrapper but keep the children."

## Proposed Solution

A new `:unwrap` directive. When the condition is true, the element is stripped and only its children are rendered. When false, the element renders normally with its children inside.

```html
<Tooltip
  description="This is the only active login method."
  :unwrap="{!@is_last_method}"
>
  <Toggle>
    <Toggle:option
      label="On"
      to="{path(enabled:"
      true)}
      active="{@enabled}"
      method="patch"
      tone="success"
    />
    <Toggle:option
      label="Off"
      to="{path(enabled:"
      false)}
      active="{!@enabled}"
      method="patch"
      disabled="{@is_last_method}"
    />
  </Toggle>
</Tooltip>
```

One child block, zero duplication. The Tooltip renders when `@is_last_method` is true. When false, the Toggle renders directly.

## Semantics

`:unwrap` is a sibling to `:if`, operating on the same element but with different behavior:

| Directive        | When `true`               | When `false`              |
| ---------------- | ------------------------- | ------------------------- |
| `:if={cond}`     | Render element + children | Render **nothing**        |
| `:unwrap={cond}` | Render **children only**  | Render element + children |

The name "unwrap" describes exactly what happens: the wrapper is removed, the children are what's left.

### Interaction with `:if`

Both directives can coexist on the same element. `:if` is evaluated first (it already is in the compiler). If `:if` is false, nothing renders. If `:if` is true, `:unwrap` then decides whether the element itself is included:

```html
<Tooltip description="..." :if="{@show_section}" :unwrap="{!@needs_tooltip}">
  <Badge label="Status" />
</Tooltip>
```

| `@show_section` | `@needs_tooltip` | Result                         |
| --------------- | ---------------- | ------------------------------ |
| `false`         | (any)            | Nothing                        |
| `true`          | `true`           | `<Tooltip>` wrapping `<Badge>` |
| `true`          | `false`          | `<Badge>` alone                |

### Works on HTML elements too

`:unwrap` is not component-specific. It works on any element:

```html
<div class="wrapper" :unwrap="{@minimal}">
  <span>Always here</span>
</div>
```

## Implementation

The change touches three files in the Orb gem. No tokenizer or parser changes are needed — the existing directive parsing infrastructure handles `:unwrap` automatically.

### 1. `lib/orb/ast/tag_node.rb` — Recognize `:unwrap` as a compiler directive

The `compiler_directives?` method gates entry into directive processing. Rather than chaining `||` for each new directive, introduce a constant set that serves as the single source of truth for which directives the compiler handles:

```ruby
# Current (line 195-197):
def compiler_directives?
  directives.any? { |k, _v| k == :if || k == :for }
end

# Proposed:
COMPILER_DIRECTIVES = %i[if unwrap for].freeze

def compiler_directives?
  directives.any? { |k, _v| COMPILER_DIRECTIVES.include?(k) }
end
```

The constant's ordering mirrors evaluation priority (`:if` first, `:for` last) and makes it trivial to add future directives without touching the method body.

### 2. `lib/orb/temple/compiler.rb` — Compile `:unwrap` into a Temple expression

Refactor `transform_directives_for_tag_node` into focused handler methods. The entry point becomes a clean pipeline that shows evaluation order at a glance, while each handler encapsulates the fetch-remove-transform logic for its directive:

```ruby
# Current (lines 157-176):
def transform_directives_for_tag_node(node)
  # First, process any :if directives
  if_directive = node.directives.fetch(:if, false)
  if if_directive
    node.remove_directive(:if)
    return [:if,
      if_directive,
      transform(node)]
  end

  # Second, process any :for directives
  for_directive = node.directives.fetch(:for, false)
  if for_directive
    node.remove_directive(:for)
    return [:orb, :for, for_directive, transform(node)]
  end

  # Last, render as a dynamic node expression
  transform(node)
end

# Proposed:
def transform_directives_for_tag_node(node)
  handle_if(node) || handle_unwrap(node) || handle_for(node) || transform(node)
end

private

def handle_if(node)
  directive = node.directives.fetch(:if, false)
  return unless directive

  node.remove_directive(:if)
  [:if, directive, transform(node)]
end

def handle_unwrap(node)
  directive = node.directives.fetch(:unwrap, false)
  return unless directive

  node.remove_directive(:unwrap)
  [:orb, :unwrap, directive, transform(node), transform_children(node)]
end

def handle_for(node)
  directive = node.directives.fetch(:for, false)
  return unless directive

  node.remove_directive(:for)
  [:orb, :for, directive, transform(node)]
end
```

The entry point reads as a priority chain: `:if` is evaluated first (can suppress everything), `:unwrap` second (can strip the wrapper), `:for` last (iterates). Each handler returns `nil` when its directive is absent, letting the chain fall through.

Note: the `:unwrap` handler carries **both** the full element (`transform(node)`) and the bare children (`transform_children(node)`). This gives the filter both branches without re-parsing.

### 3. `lib/orb/temple/filters.rb` — Generate the conditional output

Add a handler for the `:unwrap` expression:

```ruby
# Add after on_orb_if (around line 128):

# Handle an unwrap directive expression `[:orb, :unwrap, condition, element, children]`
#
# When condition is true, renders only the children (unwrapped).
# When condition is false, renders the full element with children inside.
#
# @param [String] condition The condition to be evaluated
# @param [Array] element The full element Temple expression
# @param [Array] children The children-only Temple expression
# @return [Array] compiled Temple expression
def on_orb_unwrap(condition, element, children)
  [:if, condition, compile(children), compile(element)]
end
```

This generates:

```ruby
if condition
  # children only (unwrapped)
else
  # full element with children
end
```

## Compiled Output Example

Given:

```html
<Tooltip description="Explanation" :unwrap="{!@is_last_method}">
  <Badge label="Status" />
</Tooltip>
```

The compiler produces:

```ruby
if !@is_last_method
  # Children only — Badge renders directly
  _v1 = render(Sirius2::Badge.new(label: "Status")) { }
  _v1
else
  # Full Tooltip wrapping Badge
  _v2 = render(Sirius2::Tooltip.new(description: "Explanation")) do |__orb__tooltip|
    _v1 = render(Sirius2::Badge.new(label: "Status")) { }
    _v1
  end
  _v2
end
```

The children markup appears twice in compiled output (one per branch), but only one branch executes at runtime. This is the same strategy `:if`/`else` uses in any compiled template language.

## Security Analysis

`:unwrap` introduces no new input surface, no new interpolation sites, and no new runtime primitives. Here's why, examined from an attacker's perspective.

### Threat: Code injection via the condition expression

The `:unwrap={expression}` value is a Ruby expression embedded in the template, identical to `:if={expression}`. It follows the same code path: the tokenizer extracts the attribute value, the compiler emits it as the condition in an `if` statement, and Temple's `ControlFlow` filter generates the final Ruby code.

**No new risk.** If an attacker can control the `:unwrap` condition, they can equally control any `:if` condition or `{{ }}` expression. The trust boundary is the template source itself, which is developer-authored and not user-supplied.

### Threat: Bypassing security-critical wrappers

A wrapper element might enforce a security invariant — e.g., a `<SanitizedContainer>` that escapes its children, or a CSRF token wrapper. If `:unwrap` is applied to such an element, the children would render without the security boundary.

**Same risk as `:if`.** An `:if={false}` on the same element already removes it and all its children entirely. `:unwrap` is strictly less dangerous — the children still render, they just lose the wrapper. Both are template-author decisions, not runtime user input. If a developer writes `:unwrap` on a security-critical wrapper, that's a logic bug in the template, not a vulnerability in the directive.

### Threat: Double-rendering or state mutation from duplicated children

The compiled output contains the children in both branches of the `if`/`else`. Could an attacker trigger double execution?

**No.** Standard `if`/`else` control flow guarantees mutual exclusion — exactly one branch executes per render. The duplication is in the compiled template source, not in runtime execution. This is the same pattern every compiled template language uses for conditionals.

### Threat: XSS via unwrapped content

When unwrapped, children are emitted directly into the parent context. Could this bypass output escaping?

**No.** Escaping in Orb is applied per-expression at the `{{ }}` or component render boundary, not by wrapper elements. Removing a wrapper doesn't change how child expressions are escaped. A `<Badge label={user_input} />` is escaped identically whether it's inside a `<Tooltip>` or rendered bare.

### Threat: Interaction with `:if` creating unexpected states

When both `:if` and `:unwrap` are present, `:if` is processed first (it's higher in the directive priority chain). The resulting structure is:

```ruby
if if_condition
  if unwrap_condition
    children
  else
    element_with_children
  end
end
```

**No edge case.** The nesting is straightforward. When `:if` is false, nothing renders — `:unwrap` is never evaluated. No partial-render or inconsistent-state scenario exists.

### Summary

`:unwrap` reuses the exact same compilation and escaping pipeline as `:if`. It introduces no new interpolation site, no new runtime eval, no new trust boundary. The only novel behavior is _which subtree is selected_ for rendering — and both subtrees were already present in the template, authored by the developer.

## Summary

- **3 files changed**, ~25 lines of code added (including refactoring existing directive handling)
- **0 tokenizer/parser changes** — existing directive infrastructure handles it
- Refactors `compiler_directives?` to use a constant set and `transform_directives_for_tag_node` into per-directive handler methods — both existing directives benefit from the cleaner structure
- Works on HTML elements and components equally
- Composes cleanly with `:if` (evaluated first) and `:for`
