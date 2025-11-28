# frozen_string_literal: true

module ORB
  module Temple
    class Parser
      def initialize(options = {})
        @options = options

        # Only raise errors when is used as a standalone library
        # and not within the Temple engine
        @raise_errors = !options.key?(:generator)
      end

      def call(template)
        tokenizer = ORB::Tokenizer2.new(template, **@options)
        tokens = tokenizer.tokenize!

        parser = ORB::Parser.new(tokens, **@options)
        @root = parser.parse!

        @root
      rescue ORB::Error => e
        e.set_backtrace(e.backtrace.unshift("#{@options.fetch(:filename, :nofile)}:#{e.line || 42}"))

        # Within the Temple engine, tokenizer and parser errors shouldn't be raised
        # but instead passed on to the compiler, so we can raise them there and
        # render nice error templates.
        raise if @raise_errors

        error_with_lineno(e)
      end

      private

      def error_with_lineno(error)
        return error if error.line

        trace = error.backtrace.first
        return error unless trace

        line = trace.match(/\d+\z/).to_s.to_i
        Error.new(error.message, line)
      end
    end
  end
end
