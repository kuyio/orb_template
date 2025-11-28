# frozen_string_literal: true

module ORB
  module Temple
    class Filters < ::Temple::Filter
      def initialize(options = {})
        @options = options
        @attributes_compiler = AttributesCompiler.new
      end

      # Handle an HTML tag expression `[:orb, :tag, name, attributes, content]`
      #
      # @param [String] name The name of the tag
      # @param [Array] attributes The attributes to be passed in to the tag
      # @param [Array] content (optional) child nodes of the tag
      # @return [Array] compiled Temple core expression
      def on_orb_tag(name, attributes, content = nil)
        [:html, :tag, name, @attributes_compiler.compile_attributes(attributes), compile(content)]
      end

      # Handle a component tag expression `[:orb, :component, name, attributes, content]`
      #
      # @param [String] name The name of the component
      # @param [Array<ORB::AST::Attribute>] attributes The attributes to be passed in to the component
      # @param [Array] content (optional) Temple expression
      # @return [Array] compiled Temple core expression
      def on_orb_component(node, content = [])
        tmp = unique_name

        # Lookup the component class name using the ORB lookup mechanism
        # that traverses the configured namespaces
        name = node.tag.gsub('.', '::')
        komponent = ORB.lookup_component(name)
        komponent_name = komponent || name

        block_name = "__orb__#{komponent_name.rpartition('::').last.underscore}"
        block_name = node.directives.fetch(:with, block_name)

        # We need to compile the attributes into a set of captures and a set of arguments
        # since arguments passed to the view component constructor may be defined as
        # dynamic expressions in our template, and we need to first capture their results.
        arg_captures = @attributes_compiler.compile_captures(node.attributes, tmp)
        args = @attributes_compiler.compile_komponent_args(node.attributes, tmp)

        # Construct the render call for the view component
        code = "render #{komponent_name}.new(#{args}) do |#{block_name}|"

        # Return a compiled Temple expression that captures the component render call
        # and then evaluates the result into the OutputBuffer.
        [:multi,
          *arg_captures,
          # Capture the result of the component render call into a variable
          # we can't do :dynamic here because it's probably not a complete expression
          [:block, "#{tmp} = #{code}",
            # Capture the content of the block into a separate buffer
            # [:capture, unique_name, compile(content)]
            compile(content)],
          # Output the content
          [:escape, true, [:dynamic, tmp.to_s]]]
      end

      # Handle a component slot tag expression `[:orb, :slot, name, attributes, content]`
      #
      # @param [String] name The name of the slot
      # @param [Array<ORB::AST::Attribute>] attributes the attributes to be passed in to the slot
      # @param [Array] content (optional) Temple expression for the slot content
      # @return [Array] compiled Temple expression
      def on_orb_slot(node, content = [])
        tmp = unique_name

        # We need to compile the attributes into a set of captures and a set of arguments
        # since arguments passed to the view component constructor may be defined as
        # dynamic expressions in our template, and we need to first capture their results.
        arg_captures = @attributes_compiler.compile_captures(node.attributes, tmp)
        args = @attributes_compiler.compile_komponent_args(node.attributes, tmp)

        # Prepare the slot name, parent name, and block name
        slot_name = node.slot
        parent_name = "__orb__#{node.component.underscore}"
        block_name = node.directives.fetch(:with, "__orb__#{slot_name}")

        # Construct the code to call the slot on the parent component
        code = "#{parent_name}.with_#{slot_name}(#{args}) do |#{block_name}|"

        # Return a compiled Temple expression that captures the slot call
        [:multi,
          *arg_captures,
          [:code, code], compile(content),
          [:code, "end"]]
      end

      # Handle an if block expression `[:orb, :if, condition, yes, no]`
      #
      # @param [String] condition The condition to be evaluated
      # @param [Array] yes The content to be rendered if the condition is true
      # @param [Array] no (optional) The content to be rendered if the condition is false
      # @return [Array] compiled Temple expression
      def on_orb_if(condition, yes, no = nil)
        result = [:if, condition, compile(yes)]
        result << compile(no) if no
        result
      end

      # Handle a for block expression `[:orb, :for, expression, content]`
      #
      # @param [String] expression The iterator expression to be evaluated
      # @param [Array] content The content to be rendered for each iteration
      # @return [Array] compiled Temple expression
      def on_orb_for(expression, content)
        enumerator, collection = expression.split(' in ')
        code = "#{collection}.each do |#{enumerator}|"

        [:multi,
          [:code, code], compile(content),
          [:code, "end"]]
      end

      # Handle a dynamic node expression `[:orb, :dynamic, node, content]`
      #
      def on_orb_dynamic(node, content)
        # TODO: Determine whether the node is an html_tag, component, or slot node
        tmp = unique_name
        splats = @attributes_compiler.compile_splat_attributes(node.splat_attributes)
        code = "content_tag('#{node.tag}', #{splats}) do"

        [:multi,
          [:block, "#{tmp} = #{code}", compile(content)],
          [:escape, true, [:dynamic, tmp]]]
      end
    end
  end
end
