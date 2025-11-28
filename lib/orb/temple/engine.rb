# frozen_string_literal: true

require 'temple'

module ORB
  module Temple
    class Engine < ::Temple::Engine
      # This overwrites some Temple default options or sets default options for ORB specific filters.
      # It is recommended to set the default settings only once in the code and avoid duplication. Only use
      # `define_options` when you have to override some default settings.
      define_options generator: ::Temple::Generators::StringBuffer,
        buffer_class: 'ActionView::OutputBuffer',
        format: :xhtml,
        default_tag: 'div',
        pretty: false,
        attr_quote: '"',
        sort_attrs: true,
        merge_attrs: { 'class' => ' ' },
        streaming: true,
        use_html_safe: true,
        disable_capture: false
      filter :Encoding
      filter :RemoveBOM
      use ORB::Temple::Parser
      use ORB::Temple::Compiler
      use ORB::Temple::Filters
      html :AttributeSorter
      html :AttributeMerger
      use(:AttributeRemover) { ::Temple::HTML::AttributeRemover.new(remove_empty_attrs: options[:merge_attrs].keys) }
      html :Fast
      filter :Ambles
      filter :Escapable
      filter :StaticAnalyzer
      filter :ControlFlow
      filter :MultiFlattener
      filter :StaticMerger
      use(:Generator) { options[:generator] }
    end
  end
end
