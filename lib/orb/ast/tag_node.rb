# frozen_string_literal: true

module ORB
  module AST
    ##
    # Represents a tag node in the AST.
    # A tag node is used to represent an HTML tag or a component tag.
    # The tag node contains information about the tag name, attributes, and directives.
    #
    # It is created by the parser from a Token object produced by the tokenizer.
    class TagNode < AbstractNode
      attr_reader :tag, :meta

      SLOT_SEPARATOR = ':'

      ##
      # Create a new TagNode from the given token
      #
      # @param token [Token] the token to create the node from
      #
      # @return [TagNode] the new node
      def initialize(token)
        super
        @tag = token.value
        @meta = token.meta

        # Parse attributes from the metadata
        @raw_attributes = @meta.fetch(:attributes, []).map do |attr|
          name, type, value = attr
          Attribute.new(name, type, value)
        end
      end

      ##
      # Render the node to a string
      # @api private
      def render(_context)
        raise "Not implemented"
      end

      ##
      # Determine whether the TagNode represents an HTML tag
      #
      # @return [Boolean] true if the tag is an HTML tag, false otherwise
      def html_tag?
        @tag.start_with?(/[a-z]/)
      end

      ##
      # Determine whether the TagNode represents a self-closing (void) tag
      #
      # @return [Boolean] true if the tag is self-closing, false otherwise
      def self_closing?
        @meta.fetch(:self_closing, false)
      end

      ##
      # Retrieve the attributes for the tag. Parses the internal representation
      # of attributes in the metadata payload and constructs an array of Attribute objects.
      #
      # Use this method rather than attempting to parse the +meta+ object directly.
      #
      # @return [Array<Attribute>] the attributes for the tag
      def attributes
        @attributes ||= @raw_attributes.reject(&:directive?)
        @attributes
      end

      ##
      # Retrieve the directives for the tag
      #
      # @return [Array<Array<Attribute>>] the directives for the tag
      def directives
        @directives ||= @raw_attributes
          .select(&:directive?)
          .to_h { |attr| [attr.name[1..], attr.value] }
          .transform_keys(&:to_sym)
        @directives
      end

      ##
      # Remove a directive from the tag, i.e. when it is consumed by the compiler
      #
      def remove_directive(name)
        @directives.delete(name)
      end

      ##
      # Clear all directives from the tag
      #
      def clear_directives
        @directives = {}
      end

      ##
      # Retrieve all the static attributes for the tag.
      # A static attribute is one that has a string or boolean value.
      #
      # @return [Array<Attribute>] the static attributes for the tag
      def static_attributes
        attributes.select(&:static?)
      end

      ##
      # Retrieve all the dynamic attributes for the tag.
      # A dynamic attribute is one that has an expression value.
      #
      # @return [Array<Attribute>] the dynamic attributes for the tag
      def dynamic_attributes
        attributes.select(&:dynamic?)
      end

      ##
      # Retrieve all the splat attributes for the tag.
      # A splat attribute is one that has a splat type.
      # The splat attribute is used to pass a hash of attributes to the tag at runtime.
      #
      # @return [Array<Attribute>] the splat attributes for the tag
      def splat_attributes
        attributes.select(&:splat?)
      end

      ##
      # Determine whether the TagNode represents a component tag
      # A component tag is one that starts with an uppercase letter and
      # may contain a slot call on the component.
      #
      # @return [Boolean] true if the tag is a component tag, false otherwise
      def component_tag?
        @tag.start_with?(/[A-Z]/) && @tag.exclude?(SLOT_SEPARATOR)
      end

      ##
      # Determine whether the TagNode represents a component slot tag
      # A component slot tag is of the form +Component:slot+ and is used to
      # render a slot within a component.
      #
      # @return [Boolean] true if the tag is a component slot tag, false otherwise
      def component_slot_tag?
        @tag.start_with?(/[A-Z]/) && @tag.include?(SLOT_SEPARATOR)
      end

      ##
      # Retrieve the component name from the tag
      #
      # @return [String] the component name
      def component
        @tag.split(SLOT_SEPARATOR).first
      end

      ##
      # Retrieve the slot name from the tag
      #
      # @return [String] the slot name
      def slot
        @tag.split(SLOT_SEPARATOR).last.underscore
      end

      ##
      # Retrieve the module name from the component name
      # The module name is the first part of the component name
      # separated by a period.
      #
      # For example: +MyApp::UI::Button+ would return +MyApp.UI+
      #
      # @return [String] the module name
      def component_module
        component.rsplit('.').first
      end

      ##
      # Determine whether the tag can be compiled as static HTML
      #
      # @return [Boolean] true if the tag can be compiled as static HTML, false otherwise
      def static?
        splat_attributes.empty?
      end

      ##
      # Determine whether the tag needs to be compiled as dynamic HTML
      #
      # @return [Boolean] true if the tag needs to be compiled as dynamic HTML, false otherwise
      def dynamic?
        splat_attributes.any?
      end

      ##
      # Check whether the node has any directives
      #
      # @return [Boolean] true if the directives are present, false otherwise
      def directives?
        directives.any?
      end

      def compiler_directives?
        directives.any? { |k, _v| k == :if || k == :for }
      end

      ##
      # Determine whether the tag content should be escaped or treated as verbatim
      #
      # @return [Boolean] true if the tag content should be escaped, false otherwise
      def verbatim?
        @meta.fetch(:verbatim, false)
      end
    end
  end
end
