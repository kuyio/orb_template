# The ORB Template Language for Ruby

[![Gem Version](https://badge.fury.io/rb/orb_template.svg)](https://badge.fury.io/rb/orb_template)

https://github.com/user-attachments/assets/8380b9a8-2063-40f3-a9b6-1b5d623d6f31

**ORB** is a template language for Ruby with the express goal of providing a first-class DSL for rendering [ViewComponents](https://viewcomponent.org). It is heavily inspired by [React JSX](https://react.dev/learn/writing-markup-with-jsx) and [Surface](https://surace-ui.org).

## Show me an Example

**The Old Way (ERB)**

```erb
<%= render CardComponent.new(title: "Your friends") do |card| %>
  <%= card.section(title: "Birthdays today") do %>
    <% @friends.each do |friend| %>
      <%= render ListComponent.new do %>
        <%= render List::ItemComponent.new do %>
          <%= render LinkComponent.new(url: member_path(friend)) do %>
            <%= friend.name %>
          <% end %>
        <% end %>
      <% end %>
    <% end %>
  <% end %>
<% end %>
```

**The ORB Way**

```jsx
<Card title="Your friends">
  <Card:Section title="Birthdays today">
    <List>
      <List.Item :for={friend in @friends}>
        <Link url={member_path(friend)}>{{friend.name}}</Link>
      </List.Item>
    </List>
  </Card:Section>
</Card>
```

## Table of Contents

- [Installation](#installation)
- [Motivation](#motivation)
- [Configuration](#configuration)
- [Syntax & Features](#features)
  - [HTML5](#html5)
  - [Dynamic Attributes](#dynamic-attribute-values)
  - [Splatted Attributes](#splatted-attributes)
  - [Components](#view-components)
  - [Control Flow](#control-flow)
  - [Expressions](#expressions)
  - [View Components](#view-components)
  - [Slots](#viewcomponent-slots)
  - [Namespaces](#namespaces)
  - [Comments](#comments)
- [Editor Support](#editor-support)
- [Roadmap](#roadmap)

## Installation

In your `Gemfile`, add:

```ruby
gem "orb_template"
```

then run:

```bash
bundle install
```

The gem automatically registers the `ORB` template engine as the renderer for `*.html.orb` view template files.

## Motivation

There already exist a plethora of fast, battle-proven template languages for the Ruby/Rails ecosystem, so why invent another one?

ORB was born out of the frustration that instantiating and rendering view components with existing template engines quickly becomes tedious. This hindered adoption of ViewComponents in our projects, impacted velocity, maintenance and new-developer onboarding. These effects were especially pronounced with highly customizable view components with long argument lists, as well as deeply nested components, and component trees - like a Design System / Component Library.

A common solution to making the rendering of view components less verbose is to define component-specific view helpers like so:

```ruby
module ComponentsHelper
  Components = {
    card: "Components::CardComponent",
    text: "Components::TextComponent",
    # ...
  }.freeze

  Components.each do |name, klass|
    define_method(name) do |*args, **kwargs, &block|
      capture do
        render(klass.constantize.new(*args, **kwargs)) { |com| block.call(com) if block.present? }
      end
    end
  end
end
```

You can then use these view helpers in your front-end code, wherever a view components needs to be rendered:

```erb
<%= card(title: "Your friends") do %>
  <%= text(variant: "heading") do %>
    Overview
  <% end %>
  ...
<% end %>
```

But that's still not ideal. The code is still verbose, and the heavy use of Ruby blocks makes it hard to visually parse the structure of the rendered HTML. It also introduces a lot of boilerplate code that needs to be maintained in the view helpers module. It's like pushing around food on your plate that you don't like, but just arranging it differently doesn't make it taste any better.

### The ORB Language

The `ORB` template language takes another path and allows you to write components exactly how you picture them: as elements in a document tree.

```jsx
<Card title="Your friends">
  <Card:Section title="Birthdays today">
    <List>
      <List.Item>
        <Link url={member_path(2)}>Carl Schwartz (27)</Link>
      </List.Item>
      <List.Item>
        <Link url={member_path(3)}>Floralie Brain (38)</Link>
      </List.Item>
    </List>
  </Card:Section>
</Card>
```

Your code becomes more focused, grokable and maintainable. Front-end teams that may already be familiar with JSX or VUE can become productive faster, and can make use of their existing editor tooling for HTML like `Emmet` when writing templates.

### Core Values

We believe that any template language should be enjoyable to the user:

- HTML-First: if you know HTML, you know 90% of ORB.
- Concise: reduce boilerplate as much as possible, to ease the burden of writing common and repetitive markup.
- Secure: with an option to turn off evaluation of expressions through configuration.
- Stateless Compilation: Lexing and parsing, and compilation happen once.
- Dynamic: Rendering with a context of local variables and objects is fast.
- Polite: guide the user with useful error messages when their templates contain problems.

### Conventions

- Components rendered by the `ORB` engine live under the configured namespace and omit the `Component` suffix from their class names.
- HTML view templates have a file extension of `.*.orb`, for example: `my_template.html.orb` for a template named `:my_template` that outputs in `format: :html`.

---

## Features

ORB fully supports the HTML5 markup language standard and extends HTML with additional syntax for expressions, dynamic attributes, blocks, components, slots, and comments.

### Configuration

You can configure the `ORB` engine in your Rails application with an initializer, e.g., `config/initializers/orb.rb`:

```ruby
ORB.namespace = 'MyComponents'
```

This will instruct the `ORB` engine to look for components under the `MyComponents` namespace.

### HTML5

Regular HTML tags are fully supported by `ORB`. Just write your HTML tags as you are used to and you are good to go.

```jsx
<div id="page-banner" class="banner" aria-role="alert">
  <span class="message">Hello World!</span>
</div>
```

### Expressions

`ORB` supports Ruby expressions in the code through double curly-braces (mustache-like syntax). The code inside the curly-braces will be evaluated at render time, and the result will be HTML-safe escaped and inserted into the output.:

```jsx
<div id="page-banner" class="banner" aria-role="alert">
  <span class="message">{{banner.message}}</span>
</div>
```

Should you need to execute non-printing code, for instance to assign local variables, you can use the non-printing expression syntax with percent signs:

```jsx
{% user = current_user %}

<div id="page-banner" class="banner" aria-role="alert">
  <span class="message">Welcome back, {{user.name}}!</span>
</div>
```

### Dynamic Attribute Values

The `ORB` language allows you to define dynamic attribute values for HTML tags through single curly-braces. The code will be evaluated at render time, and assigned to the HTML attribute as a HTML-safe escaped string.

Example:

```jsx
<div id={dom_id(banner)} class={banner.classes}>
  <span class="message">{{banner.message}}</span>
</div>
```

### Control Flow

`ORB` supports flow control constructs through block instructions. The general syntax for a block is:

```jsx
{#blockname expression} ... {/blockname}
```

For example, a `Banner` may be conditionally rendered through an `{#if}` block construct like this:

```jsx
{#if banner.urgent?}
  <div id={dom_id(banner)} class={banner.classNames}>
    <span class="message">{{banner.message}}</span>
  </div>
{/if}
```

Since control flow is such a common thing in templates, `ORB` provides special syntactic sugar for the `{#if}` and `{#for}` blocks through the `:if` and `:for` directives on HTML tags. The above example can thus be rewritten as:

```jsx
<div id={dom_id(banner)} class={banner.classNames} :if={banner.urgent?}>
  <span class="message">{{banner.message}}</span>
</div>
```

#### The `:unwrap` Directive

The `:unwrap` directive conditionally strips a wrapper element while keeping its children. When the condition is true, only the children are rendered. When false, the element renders normally with its children inside.

```jsx
<div class="tooltip-wrapper" :unwrap={!@needs_tooltip}>
  <span>Always rendered</span>
</div>
```

| `:unwrap` condition | Result |
|---|---|
| `true` | Children only (`<span>Always rendered</span>`) |
| `false` | Full element (`<div class="tooltip-wrapper"><span>...</span></div>`) |

This eliminates the need to duplicate child markup when a wrapper is conditional:

```jsx
{!-- Before: duplicated children --}
<Tooltip :if={@is_last_method} description="Only active method.">
  <Toggle><Toggle:Option label="On" /><Toggle:Option label="Off" /></Toggle>
</Tooltip>
{#if !@is_last_method}
  <Toggle><Toggle:Option label="On" /><Toggle:Option label="Off" /></Toggle>
{/if}

{!-- After: single child block, zero duplication --}
<Tooltip description="Only active method." :unwrap={!@is_last_method}>
  <Toggle><Toggle:Option label="On" /><Toggle:Option label="Off" /></Toggle>
</Tooltip>
```

`:unwrap` works on both HTML elements and components. It can be combined with `:if` on the same element -- `:if` is evaluated first:

```jsx
<Tooltip description="..." :if={@show_section} :unwrap={!@needs_tooltip}>
  <Badge label="Status" />
</Tooltip>
```

| `@show_section` | `@needs_tooltip` | Result |
|---|---|---|
| `false` | (any) | Nothing |
| `true` | `true` | `<Tooltip>` wrapping `<Badge>` |
| `true` | `false` | `<Badge>` alone |

### Splatted Attributes

`ORB` supports attribute splatting for both HTML tags and view components through the `**attributes` syntax. The attribute name for the splat must be a `Hash`; all key-value pairs will be added as attributes to the tag. For example:

```jsx
<div **banner_attributes>
  <!-- other content ... -->
</div>
```

### Splatted Attribute Expressions

You can also use an expression to define the splatted attributes through the `**{expression}` syntax. The expression must evaluate to a `Hash`, and all key-value pairs will be added as attributes to the tag. For example:

```jsx
<div **{dynamic_attributes(member)}>
  <!-- other content ... -->
</div>
```

### View Components

In `ORB` templates, you can render ViewComponents as if they were HTML tags. The `Component` suffix on ViewComponents may be omitted to make the markup nicer.

For example, if you have a `Button` view component that may be defined as:

```ruby
class MyComponents::Button < ViewComponent::Base
  def initialize(url: "#", **options)
    @url = url
    @options = options
  end

  erb_template <<-ERB
    <%= link_to(@url, **@options.merge(class: "btn btn-primary")) do %>
      <%= content %>
    <% end %>
  ERB
end
```

You can render this component in an ORB template `show.html.orb` as:

```jsx
<Button url="/click_me">I am a button</Button>
```

### Inline Templates

You can define the markup for a component inline using `orb_template` to use the ORB template language for the component's own view template:

```ruby
class ButtonComponent < ViewComponent::Base
  def initialize(url:)
    @url = url
  end

  orb_template <<~ORB
    <a href={@url} class="btn">{{ content }}</a>
  ORB
end
```

If your template needs string interpolation, you have several options:

```ruby
# 1. Single-quoted heredoc (recommended) — #{} is preserved for render time
orb_template <<~'ORB'
  <div id={"#{@id}_suffix"}>Hello</div>
ORB

# 2. String concatenation — avoids #{} entirely
orb_template <<~ORB
  <div id={@id + "_suffix"}>Hello</div>
ORB

# 3. Helper method — move the interpolation into Ruby
orb_template <<~ORB
  <div id={suffixed_id}>Hello</div>
ORB

def suffixed_id
  "#{@id}_suffix"
end
```

### ViewComponent Slots

`ORB` also provides a DSL for invoking a component slot and passing content to the slot through the `Component:Slot` syntax. For example, if you have a `Card` component that defines a `Sections` slot via `renders_many :sections, Card::Section`, you can invoke and fill the slot in an `ORB` template like this:

```jsx
<Card title="Products">
  <Card:Section title="Description">
    <p>Blue t-shirt in size L ...</p>
  </Card:Section>
</Card>
```

Tip: Slot names are case-insensitive, so `<Card:section> ... </Card:section>` also works.

### Namespaces

Sometimes, you may want to organize your components in sub-namespaces, or use components from other libraries. `ORB` supports this through dot notation in the tag names. For example, if you have a `MyComponents::Admin::Button` component, you can render it in an `ORB` template like this:

```jsx
<Admin.Button url="/admin/click_me">Admin Button</Admin.Button>
```

If you have a third-party component `ThirdParty::UI::Modal`, you can render it like this:

```jsx
<ThirdParty.UI.Modal title="Terms and Conditions">
  <p>...</p>
</ThirdParty.UI.Modal>
```

To make life easier when using components from a specific namespace frequently, you can configure additional namespaces in the `ORB` configuration:

```ruby
ORB.namespaces = ['MyComponents', 'ThirdParty::UI']
```

Namespaces defined in this way will be searched in order of definition when resolving component tag names in templates.

### Comments

**Public comments** are sent to the browser, and can be read by users inspecting the page source. ORB considers default HTML comments `<!-- -->` to be public comments.

```html
<!-- I will be sent to the browser -->
<p>Hello World!</p>
```

**Private comments**, unlike public comments, won't be sent to the browser. Use private comments to mark up your ORB template with annotations that you do not wish users to see.

```ruby-orb
{!-- I won't be sent to the browser --}
<p>Hello World!</p>
```

## Editor support

- `VSCode` through the [ORB VSCode Extension](https://github.com/kuyio/vscode-orb).
- `Zed` through the [ORB Zed Extension](https://github.com/kuyio/zed-orb).
- Others through the [ORB Treesitter Grammer](https://github.com/kuyio/tree-sitter-orb).

Your favorite editor is not listed? Feel free to contribute an extension/plugin for your editor of choice!

### Visual Studio Code

To enable `Emmet` support for ORB, add this to your `settings.json`:

```json
"emmet.includeLanguages": {
  "ruby-orb": "html",
}
```

To enable `Tailwindcss` support for ORB, add this to your `settings.json`:

```json
"tailwindCSS.includeLanguages": {
  "ruby-orb": "html"
}
```

## Roadmap

- [x] **Step 1: Make it work**
  - [x] streaming Lexer based on HTML spec state machine
  - [x] parse token stream into AST
  - [x] properly handle void tags and mark void-tags as self-closing
  - [x] support standard HTML tags (`<div>...</div>`)
  - [x] support dynamic attributes (`foo={bar}`)
  - [x] support expressions (`{{ ... }}`)
  - [x] public comments (`<!-- -->`), and private comments (`{!-- --}`)
  - [x] support non-printing expressions (`{% ... %}`)
  - [x] support conditional blocks (`{#if ...}`)
  - [x] support iterative blocks (`{#for ...}` )
  - [x] support component tags (`<Card> ... </Card>`)
  - [x] support slot tags (`<Card:section> ... </Card:section>`)
  - [x] compile AST to Temple core expressions
  - [x] a Temple engine that renders to HTML with useful pre- and post-processing steps to generate well-formed output
  - [x] a Railtie that automatically registers ORB's temple engine as handler for `*.orb` templates
  - [x] basic test suite covering lexer, parser, compiler
  - [x] basic errors for lexer, parser, compiler
  - [x] Extensions for code editor support
- [ ] **Step 2: Make it nice**
  - [x] improved errors with super helpful error messages and locations throughout the entire stack, possibly custom rendered error pages
  - [x] `**attribute` splats for html tags, components and slots
  - [x] `**{expression}` splats for html tags, components and slots
  - [x] `:if` directive
  - [x] `:for` directive
  - [x] `:unwrap` directive
  - [x] verbatim tags
  - [x] ensure output safety and proper escaping of output
  - [x] security review and hardening of compilation pipeline
  - [x] track locations (start_line, start_col, end_line, end_col) for Tokens and AST Nodes to support better error output
  - [x] make Lexer, Parser, Compiler robust to malformed input (e.g., unclosed tags)
  - [ ] emit an warning/error when void tags contain children
  - [ ] support for special comments, like `CDATA`
  - [ ] support sub-blocks (`{#else}`, `{#elsif}`, ...)
  - [ ] support `{#cond ...}` blocks
  - [ ] support `{#case ...}` blocks
  - [ ] support `{#unless ...}` blocks
  - [ ] support raw output `{= ...}}` blocks
  - [ ] `:show` directive
  - [ ] include render tests in test suite
  - [ ] make template engine configurable
  - [ ] support embedded languages like `embedded ruby`, `markdown`, `rdoc`, `sass`, `scss`, `javascript`, `css`, ...
  - [ ] compile AST to a StringBuffer so library can be used standalone / outside of Rails
  - [ ] full YARD-compatible documentation of the library
- [ ] **Step 3: Make it fast**
  - [x] convert Lexer code to `StringScanner`
  - [x] create benchmark suite to establish baseline
  - [ ] possibly merge lexer states through more intelligent look-ahead
  - [x] optimize AST Parser
  - [x] optimize Compiler
- [ ] **Step 4: Evolve**
  - [ ] support additional directives, for instance, `Turbo` or `Stimulus` specific directives
  - [ ] support additional block constructs
  - [ ] support additional language constructs
  - [ ] replace `OpenStruct`-based `RenderContext` with a `BasicObject` subclass to reduce attack surface
  - [ ] fuzz testing of tokenizer and parser for edge case discovery
  - [ ] Brakeman integration with custom rules to flag unsafe ORB patterns
  - [ ] tighten `TAG_NAME` pattern at the tokenizer level as defense-in-depth

## Security

ORB follows the same trust model as ERB, HAML, and SLIM: templates are developer-authored and loaded from the filesystem. **Never construct ORB templates from user input.**

The compilation pipeline has been hardened against code injection, XSS, and denial-of-service attacks:

- All values interpolated into generated Ruby code (`:for` expressions, `:with` directives, tag names, component names, slot names) are validated against strict patterns before interpolation.
- Dynamic attribute values (`class={expr}`) are HTML-escaped at render time, matching the escaping behavior of printing expressions (`{{expr}}`).
- Attribute names are restricted to valid HTML spec characters.
- Resource limits are enforced: maximum brace nesting depth (100) and maximum template size (2MB).

For details, see [`docs/2026-03-12-security-analysis.md`](docs/2026-03-12-security-analysis.md).

## Development

To set up your development environment, follow these steps:

1. Clone the repository:

   ```bash
   git clone https://github.com/kuyio/orb_template.git
   cd orb_template
   ```

2. Install dependencies:

   ```bash
   bundle install
   ```

3. Run the test suite to ensure everything is set up correctly:

   ```bash
   make test
   ```

4. Start the development server for the test application:

   ```bash
   bin/rails server
   ```

## Contributing

This project is intended to be a safe, welcoming space for collaboration. Contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct. We recommend reading the [contributing guide](./docs/CONTRIBUTING.md) as well.

## License

ORB is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
