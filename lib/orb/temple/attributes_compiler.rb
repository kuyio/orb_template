# frozen_string_literal: true

module ORB
  module Temple
    class AttributesCompiler
      def initialize(options = {})
        @options = options
      end

      # Compile the given array of AST::Attribute objects into Temple capture expressions
      # using the given prefix in variable names
      def compile_captures(attributes, prefix)
        result = []

        attributes.each do |attribute|
          # TODO: handle splat attributes
          next if attribute.splat?

          # generate a unique variable name for the attribute
          var_name = prefixed_variable_name(attribute.name, prefix)

          # inject a code expression for the attribute value and assign to the variable
          if attribute.string?
            result << [:code, "#{var_name} = \"#{attribute.value}\""]
          elsif attribute.bool?
            result << [:code, "#{var_name} = true"]
          elsif attribute.expression?
            result << [:code, "#{var_name} = #{attribute.value}"]
          end
        end

        result
      end

      # Compile the given array of AST::Attribute objects into a string of arguments
      # the can be used in a ViewComponent constructor call, as long as the
      # compiled captures are available in the same scope.
      def compile_komponent_args(attributes, prefix)
        args = {}
        splats = []

        attributes.each do |attribute|
          if attribute.splat?
            # Splat attribute values already include the ** prefix
            splats << attribute.value
          else
            var_name = prefixed_variable_name(attribute.name, prefix)
            args = args.deep_merge(dash_to_hash(attribute.name, var_name))
          end
        end

        # Build the argument list
        result_parts = []
        result_parts << hash_to_args_list(args) unless args.empty?
        result_parts += splats

        result_parts.join(', ')
      end

      # Compile the attributes of a node into a Temple core abstraction
      def compile_attributes(attributes)
        temple = [:html, :attrs]

        attributes.each do |attribute|
          # Ignore splat attributes
          next if attribute.splat?

          temple << compile_attribute(attribute)
        end

        temple
      end

      ##
      # Compile splat attributes to a code string
      def compile_splat_attributes(attributes)
        attributes.map(&:value).join(',')
      end

      # Compile a single attribute into Temple core abstraction
      # an attribute can be a static string, a dynamic expression,
      # or a boolean attribute (an attribute without a value, e.g. disabled, checked, etc.)
      #
      # For boolean attributes, we return a [:dynamic, "nil"] expression, so that the
      # final render for the attribute will be `attribute` instead of `attribute="true"`
      def compile_attribute(attribute)
        if attribute.string?
          [:html, :attr, attribute.name, [:static, attribute.value]]
        elsif attribute.bool?
          [:html, :attr, attribute.name, [:dynamic, "nil"]]
        elsif attribute.expression?
          [:html, :attr, attribute.name, [:dynamic, attribute.value]]
        end
      end

      def dash_to_hash(name, value)
        parts = name.split('-')
        parts.reverse.inject(value) { |a, n| { n => a } }
      end

      def hash_to_args_list(obj, level = -1)
        case obj
        when String
          obj
        when Array
          obj.map { |v| hash_to_args_list(v, level + 1) }.join(", ")
        when Hash
          down_the_rabbit_hole = obj.map { |k, v| "#{k}: #{hash_to_args_list(v, level + 1)}" }.join(", ")
          return down_the_rabbit_hole if level.negative?

          "{#{down_the_rabbit_hole}}"

        else
          raise "Invalid argument passed to hash_to_args_list: #{obj.inspect}"
        end
      end

      def prefixed_variable_name(name, prefix)
        "#{prefix}_arg_#{name.underscore}"
      end
    end
  end
end
