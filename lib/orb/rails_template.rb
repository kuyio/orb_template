# frozen_string_literal: true

module ORB
  class RailsTemplate
    require 'orb/utils/orb'
    # Compatible with: https://github.com/judofyr/temple/blob/v0.7.7/lib/temple/mixins/options.rb#L15-L24
    class << self
      def options
        @options ||= {
          generator: ::Temple::Generators::RailsOutputBuffer,
          use_html_safe: true,
          streaming: true,
          buffer_class: 'ActionView::OutputBuffer',
          disable_capture: true,
        }
      end

      def set_options(opts)
        options.update(opts)
      end
    end

    def call(template, source = nil)
      source ||= template.source
      options = RailsTemplate.options

      # Make the filename available in parser etc.
      options = options.merge(file: template.identifier) if template.respond_to?(:identifier)

      # Set type
      options = options.merge(format: :xhtml) if template.respond_to?(:type) && template.type == 'text/xml'

      # Annotations
      if ActionView::Base.try(:annotate_rendered_view_with_filenames) && template.format == :html
        options = options.merge(
          preamble: "<!-- BEGIN #{template.short_identifier} -->\n",
          postamble: "<!-- END #{template.short_identifier} -->\n",
        )
      end

      # Pipe through the ORB Temple engine
      ORB::Temple::Engine.new(options).call(source)
    end

    # See https://github.com/rails/rails/pull/47005
    def translate_location(spot, backtrace_location, source)
      offending_line_source = source.lines[backtrace_location.lineno - 1]
      tokens = ORB::Utils::ORB.tokenize(offending_line_source)
      new_column = find_offset(spot[:snippet], tokens, spot[:first_column])

      lineno_delta = spot[:first_lineno] - backtrace_location.lineno
      spot[:first_lineno] -= lineno_delta
      spot[:last_lineno] -= lineno_delta

      column_delta = spot[:first_column] - new_column
      spot[:first_column] -= column_delta
      spot[:last_column] -= column_delta
      spot[:script_lines] = source.lines

      spot
    rescue StandardError => _e
      spot
    end

    def find_offset(snippet, src_tokens, snippet_error_column)
      offset = 0
      passed_tokens = []

      # Pass over tokens until we are just over the snippet error column
      # then the column of the last token is the offset (without the token static offset for tags {% %})
      while (tok = src_tokens.shift)
        offset = snippet.index(tok.value, offset)
        raise "text not found" unless offset
        raise "we went too far" if offset > snippet_error_column

        passed_tokens << tok
      end
    rescue StandardError
      offset_token = passed_tokens.last
      offset_from_token(offset_token)
    end

    def offset_from_token(token)
      case token.type
      when :tag_open, :tag_close
        token.column + 1
      when :public_comment, :private_comment
        token.column + 4
      when :block_open, :block_close
        token.column + 2 + token.value.length
      when :printing_expression, :control_expression
        token.column + 2
      end
    end

    def supports_streaming?
      RailsTemplate.options[:streaming]
    end
  end
  ActionView::Template.register_template_handler(:orb, RailsTemplate.new) if defined?(ActionView)
end
