# frozen_string_literal: true

require_relative 'test_helper'
require 'benchmark'

class BenchmarkTest < Minitest::Test
  # Number of iterations per benchmark.
  # Tuned so each test completes in a few seconds while still being stable.
  N = Integer(ENV.fetch('BENCH_N', 2000))

  # Maximum allowed milliseconds per compilation for each template category.
  # These are generous ceilings, not targets — they exist to catch major
  # regressions, not micro-optimisations.  Adjust as hardware changes.
  THRESHOLDS = {
    minimal:          1.0,   # ms per compilation
    static_heavy:     3.0,
    expression_heavy: 10.0,
    control_flow:     2.0,
    attributes_mixed: 3.0,
    component_like:   4.0,
    deeply_nested:    4.0,
    realistic_page:   8.0,
  }.freeze

  # -------------------------------------------------------------------
  # Templates — each stresses a different part of the pipeline
  # -------------------------------------------------------------------

  TEMPLATES = {
    # 1. Minimal: near-empty template — measures baseline overhead
    minimal: '<div>hello</div>',

    # 2. Static-heavy: lots of plain HTML, very few expressions
    static_heavy: <<~ORB,
      <html>
        <head><title>Static</title></head>
        <body>
          <header><nav><ul><li>Home</li><li>About</li><li>Contact</li></ul></nav></header>
          <main>
            <section><h1>Title</h1><p>Paragraph one.</p><p>Paragraph two.</p></section>
            <section><h2>Subtitle</h2><p>More text here.</p></section>
            <aside><p>Sidebar content</p></aside>
          </main>
          <footer><p>Copyright 2026</p></footer>
        </body>
      </html>
    ORB

    # 3. Expression-heavy: many dynamic attribute expressions
    expression_heavy: (1..30).map { |i|
      %(<div id={x#{i}} class={y#{i}} data-v={z#{i}}>{{ v#{i} }}</div>)
    }.join("\n"),

    # 4. Control flow: if/for blocks
    control_flow: <<~ORB,
      {#if @show}
        {#for item in @items}
          {#if item.active?}
            <span>{{ item.name }}</span>
          {/if}
        {/for}
      {/if}
      {#for key, value in @metadata}
        <div>{{ key }}: {{ value }}</div>
      {/for}
      {#for i in (1..10)}
        <span>{{ i }}</span>
      {/for}
    ORB

    # 5. Mixed attributes: static strings, booleans, and expressions
    attributes_mixed: <<~ORB,
      <input type="text" name="email" id={@field_id} value={@email} required disabled class="form-control" data-validate={@rules}>
      <select name="country" id={@select_id} class="form-select" data-default={@default_country}>
        {#for country in @countries}
          <option value={country.code} selected>{{ country.name }}</option>
        {/for}
      </select>
      <button type="submit" class="btn btn-primary" data-loading={@loading} data-action={@submit_action}>Submit</button>
    ORB

    # 6. Component-like: simulates ViewComponent render patterns with nested tags
    component_like: <<~ORB,
      <div class="card" id={@card_id}>
        <div class="card-header">
          <h3>{{ @title }}</h3>
          {#if @subtitle}
            <p class="subtitle">{{ @subtitle }}</p>
          {/if}
        </div>
        <div class="card-body">
          {#for section in @sections}
            <div class={section.class} id={section.id}>
              <h4>{{ section.heading }}</h4>
              <p>{{ section.body }}</p>
              {#if section.footer}
                <footer>{{ section.footer }}</footer>
              {/if}
            </div>
          {/for}
        </div>
        <div class="card-footer" data-actions={@footer_actions}>
          <span>{{ @footer_text }}</span>
        </div>
      </div>
    ORB

    # 7. Deeply nested: tests recursive compilation depth
    deeply_nested: 10.times.inject('<span>{{ @leaf }}</span>') { |inner, i|
      %(<div class="level-#{i}" id={@id_#{i}} data-depth={#{i}}>#{inner}</div>)
    },

    # 8. Realistic page: a full-page-ish template combining everything
    realistic_page: <<~ORB,
      <html>
      <head><title>{{ @page_title }}</title></head>
      <body>
        <header class="header" id={@header_id}>
          <nav>
            {#for link in @nav_links}
              <a href={link.url} class={link.active? ? "active" : ""}>{{ link.label }}</a>
            {/for}
          </nav>
        </header>
        <main>
          {#if @alert}
            <div class="alert" data-type={@alert.type}>{{ @alert.message }}</div>
          {/if}
          <h1>{{ @heading }}</h1>
          <div class="grid">
            {#for card in @cards}
              <div class="card" id={card.id} data-category={card.category}>
                <img src={card.image_url} alt={card.title}>
                <h2>{{ card.title }}</h2>
                <p>{{ card.description }}</p>
                {#if card.tags}
                  <div class="tags">
                    {#for tag in card.tags}
                      <span class="tag">{{ tag }}</span>
                    {/for}
                  </div>
                {/if}
                <footer>
                  <span>{{ card.author }}</span>
                  <time datetime={card.date}>{{ card.formatted_date }}</time>
                </footer>
              </div>
            {/for}
          </div>
          <nav class="pagination">
            {#for page in @pages}
              <a href={page.url} class={page.current? ? "current" : ""}>{{ page.number }}</a>
            {/for}
          </nav>
        </main>
        <footer class="site-footer">
          <p>{{ @copyright }}</p>
        </footer>
      </body>
      </html>
    ORB
  }.freeze

  # Shared engine options (no Rails OutputBuffer needed for compilation benchmarks)
  ENGINE_OPTS = {
    generator: ::Temple::Generators::StringBuffer,
    use_html_safe: true,
    streaming: true,
    buffer_class: 'ActionView::OutputBuffer',
  }.freeze

  # -------------------------------------------------------------------
  # Full-pipeline benchmarks — one test per template
  # -------------------------------------------------------------------

  TEMPLATES.each do |name, template|
    define_method(:"test_benchmark_#{name}") do
      # Warm up
      5.times { compile(template) }

      elapsed = measure { N.times { compile(template) } }
      ms_per = (elapsed / N) * 1000

      threshold = THRESHOLDS.fetch(name)
      puts format("\n  %-25s %8.3f ms/compile  (%.2fs total, n=%d)", name, ms_per, elapsed, N)
      assert ms_per < threshold,
        "#{name} compilation too slow: #{ms_per.round(3)} ms/compile exceeds #{threshold} ms threshold"
    end
  end

  # -------------------------------------------------------------------
  # Stage-level breakdown — profiles tokenizer, parser, compiler, filters
  # -------------------------------------------------------------------

  def test_benchmark_stage_breakdown
    template = TEMPLATES[:realistic_page]

    # Warm up
    5.times { compile(template) }

    puts "\n  Stage breakdown (#{N} iterations, realistic_page template):"

    tokenize_time = measure { N.times { ORB::Tokenizer2.new(template).tokenize } }
    puts format("    %-30s %8.3f ms/iter", "tokenize", (tokenize_time / N) * 1000)

    tokens = ORB::Tokenizer2.new(template).tokenize
    parse_time = measure { N.times { ORB::Parser.new(tokens).parse } }
    puts format("    %-30s %8.3f ms/iter", "parse", (parse_time / N) * 1000)

    ast = ORB::Parser.new(tokens).parse
    compiler = ORB::Temple::Compiler.new
    compile_time = measure { N.times { compiler.call(ast) } }
    puts format("    %-30s %8.3f ms/iter", "compile (AST -> Temple IR)", (compile_time / N) * 1000)

    temple_ir = compiler.call(ast)
    filter_time = measure { N.times { ORB::Temple::Filters.new.call(temple_ir) } }
    puts format("    %-30s %8.3f ms/iter", "filters", (filter_time / N) * 1000)

    full_time = measure { N.times { compile(template) } }
    puts format("    %-30s %8.3f ms/iter", "full pipeline", (full_time / N) * 1000)

    pass # always pass — this test is for visibility, not gating
  end

  # -------------------------------------------------------------------
  # Temple IR node count — tracks AST bloat over time
  # -------------------------------------------------------------------

  def test_benchmark_node_counts
    puts "\n  Temple IR node counts:"

    TEMPLATES.each do |name, template|
      tokens = ORB::Tokenizer2.new(template).tokenize
      ast = ORB::Parser.new(tokens).parse
      temple_ir = ORB::Temple::Compiler.new.call(ast)
      filtered = ORB::Temple::Filters.new.call(temple_ir)

      ir_count = count_nodes(temple_ir)
      filtered_count = count_nodes(filtered)

      puts format("    %-25s IR: %4d  Filtered: %4d", name, ir_count, filtered_count)
    end

    pass # informational
  end

  private

  def compile(template)
    ORB::Temple::Engine.new(ENGINE_OPTS).call(template)
  end

  def measure
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  end

  def count_nodes(ir)
    return 0 unless ir.is_a?(Array)
    1 + ir.sum { |child| count_nodes(child) }
  end
end
