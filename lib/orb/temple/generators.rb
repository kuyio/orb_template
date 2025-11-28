# frozen_string_literal: true

# TODO: This class is a WIP and not used in production code, yet.
#
# Eventually this class will be used to generate the Ruby code from the AST.
# It tries to match the behaviour of the rails ERB Template handler as close as possible.
module ORB
  module Temple
    module Generators
      class Generator
        include Utils
        include Mixins::CompiledDispatcher
        include Mixins::Options

        define_options :save_buffer,
          :streaming,
          capture_generator: 'Generator',
          buffer_class: 'ActionView::OutputBuffer',
          buffer: '@output_buffer',
          freeze_static: true

        def call(exp)
          [preamble, compile(exp), postamble].flatten.compact.join('; ')
        end

        def preamble
          [save_buffer, create_buffer]
        end

        def postamble
          [return_buffer, restore_buffer]
        end

        def save_buffer
          "begin; #{@original_buffer = unique_name} = #{buffer} if defined?(#{buffer})" if options[:save_buffer]
        end

        def restore_buffer
          "ensure; #{buffer} = #{@original_buffer}; end" if options[:save_buffer]
        end

        def create_buffer
          if buffer == '@output_buffer'
            "#{buffer} = output_buffer || #{options[:buffer_class]}.new"
          else
            "#{buffer} = #{options[:buffer_class]}.new"
          end
        end

        def return_buffer
          'nil'
        end

        def on(*exp)
          raise InvalidExpression, "Generator supports only core expressions - found #{exp.inspect}"
        end

        def on_multi(*exp)
          exp.map { |e| compile(e) }.join('; ')
        end

        def on_newline
          "\n"
        end

        def on_capture(name, exp)
          capture_generator.new(capture_generator: options[:capture_generator],
            freeze_static: options[:freeze_static],
            buffer: name).call(exp)
        end

        def on_static(text)
          concat(options[:freeze_static] ? "#{text.inspect}.freeze" : text.inspect)
        end

        def on_dynamic(code)
          concat(code)
        end

        def on_code(code)
          code
        end

        protected

        def buffer
          options[:buffer]
        end

        def capture_generator
          @capture_generator ||= if Class === options[:capture_generator]
                                   options[:capture_generator]
                                 else
                                   Generators.const_get(options[:capture_generator])
                                 end
        end

        def safe_concat(str)
          "#{buffer}.safe_append=#{str}"
        end

        def concat(str)
          "#{buffer}.append=#{str}"
        end
      end
    end
  end
end
