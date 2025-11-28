# frozen_string_literal: true

# HACK DO NOT USE - THIS IF FOR DEBUGGING ERB ERROR SPOT HIGHLIGHTING ONLY
module ORB
  class RailsDerp
    class << self
      def call(template, source = nil)
        new.call(template, source)
      end
    end

    # Specify trim mode for the ERB compiler. Defaults to '-'.
    # See ERB documentation for suitable values.
    class_attribute :erb_trim_mode, default: "-"

    # Default implementation used.
    # class_attribute :erb_implementation, default: Erubi

    # Do not escape templates of these mime types.
    class_attribute :escape_ignore_list, default: ["text/plain"]

    # Strip trailing newlines from rendered output
    class_attribute :strip_trailing_newlines, default: false

    ENCODING_FLAG = '#.*coding[:=]\s*(\S+)[ \t]*'
    ENCODING_TAG = Regexp.new("\\A(<%#{ENCODING_FLAG}-?%>)[ \\t]*")

    # Translate an error location returned by ErrorHighlight to the correct
    # source location inside the template.
    def translate_location(spot, backtrace_location, source)
      Rails.logger.debug "in translate_location"
      Rails.logger.debug ""
      Rails.logger.debug spot
      Rails.logger.debug ""
      Rails.logger.debug backtrace_location
      Rails.logger.debug ""
      Rails.logger.debug source

      # Tokenize the source line
      tokens = ORB::Utils::ERB.tokenize(source.lines[backtrace_location.lineno - 1])
      new_first_column = find_offset(spot[:snippet], tokens, spot[:first_column])
      lineno_delta = spot[:first_lineno] - backtrace_location.lineno
      spot[:first_lineno] -= lineno_delta
      spot[:last_lineno] -= lineno_delta

      column_delta = spot[:first_column] - new_first_column
      spot[:first_column] -= column_delta
      spot[:last_column] -= column_delta
      spot[:script_lines] = source.lines

      spot
    end

    def call(template, source)
      # First, convert to BINARY, so in case the encoding is
      # wrong, we can still find an encoding tag
      # (<%# encoding %>) inside the String using a regular
      # expression
      template_source = source.b

      erb = template_source.gsub(ENCODING_TAG, "")
      encoding = ::Regexp.last_match(2)

      erb.force_encoding valid_encoding(source.dup, encoding)

      # Always make sure we return a String in the default_internal
      erb.encode!

      # Strip trailing newlines from the template if enabled
      erb.chomp! if strip_trailing_newlines

      options = {
        escape: (self.class.escape_ignore_list.include? template.type),
        trim: (self.class.erb_trim_mode == "-")
      }

      if ActionView::Base.annotate_rendered_view_with_filenames && template.format == :html
        options[:preamble] = "@output_buffer.safe_append='<!-- BEGIN #{template.short_identifier} -->';"
        options[:postamble] = "@output_buffer.safe_append='<!-- END #{template.short_identifier} -->';@output_buffer"
      end

      ActionView::Template::Handlers::ERB::Erubi.new(erb, options).src
    end

    private

    def valid_encoding(string, encoding)
      # If a magic encoding comment was found, tag the
      # String with this encoding. This is for a case
      # where the original String was assumed to be,
      # for instance, UTF-8, but a magic comment
      # proved otherwise
      string.force_encoding(encoding) if encoding

      # If the String is valid, return the encoding we found
      return string.encoding if string.valid_encoding?

      # Otherwise, raise an exception
      raise WrongEncodingError.new(string, string.encoding)
    end

    def find_offset(compiled, source_tokens, error_column)
      compiled = StringScanner.new(compiled)

      passed_tokens = []

      while (tok = source_tokens.shift)
        tok_name, str = *tok
        case tok_name
        when :TEXT
          raise unless compiled.scan(str)
        when :CODE
          raise "We went too far" if compiled.pos > error_column

          if compiled.pos + str.bytesize >= error_column
            offset = error_column - compiled.pos
            return passed_tokens.map(&:last).join.bytesize + offset
          else
            raise unless compiled.scan(str)
          end
        when :OPEN, :CLOSE
          next_tok = source_tokens.first.last
          loop do
            break if compiled.match?(next_tok)

            compiled.getch
          end
        else
          raise NotImplemented, tok.first
        end

        passed_tokens << tok
      end
    end
  end

  ActionView::Template.register_template_handler(:derp, RailsDerp.new)
end
