# frozen_string_literal: true

module ORB
  module Temple
    # The Compiler is used in the ORB::Engine to compile an input document string
    # into a Temple expression that gets passed on to the next step in the pipeline.
    class Compiler
      # The Compiler is initialized by the Engine pipeline with the options passed to the Engine
      def initialize(options = {})
        @options = options
        @identity = Identity.new
      end

      # Then the pipeline executes the #call method with an ORB::AST::*Node input
      def call(ast)
        return runtime_error(ast) if ast.is_a?(ORB::Error)

        transform(ast)
      rescue CompilerError => e
        raise e
      rescue ORB::Error => e
        runtime_error(e)
      end

      private

      # Entry point for the compiler, dispatches to the appropriate method based on the node type
      # The `context` argument is used to pass information down the tree of nodes
      # The compile method is usually called on a root node, which then calls `compile` on its children
      # even though it can be called on any node in the AST to compile the subtree under that node.
      #
      # rubocop:disable Metrics/CyclomaticComplexity
      # rubocop:disable Metrics/PerceivedComplexity
      def transform(node, context = {})
        if node.is_a?(ORB::AST::RootNode)
          transform_children(node, context)
        elsif node.is_a?(ORB::AST::TextNode)
          transform_text_node(node, context)
        elsif node.is_a?(ORB::AST::PrintingExpressionNode)
          transform_printing_expression_node(node, context)
        elsif node.is_a?(ORB::AST::ControlExpressionNode)
          transform_control_expression_node(node, context)
        elsif node.is_a?(ORB::AST::TagNode) && node.compiler_directives?
          transform_directives_for_tag_node(node, context)
        elsif node.is_a?(ORB::AST::TagNode) && node.dynamic?
          transform_dynamic_tag_node(node, context)
        elsif node.is_a?(ORB::AST::TagNode) && node.html_tag?
          transform_html_tag_node(node, context)
        elsif node.is_a?(ORB::AST::TagNode) && node.component_tag?
          transform_component_tag_node(node, context)
        elsif node.is_a?(ORB::AST::TagNode) && node.component_slot_tag?
          transform_component_slot_tag_node(node, context)
        elsif node.is_a?(ORB::AST::BlockNode)
          transform_block_node(node, context)
        elsif node.is_a?(ORB::AST::PublicCommentNode)
          transform_public_comment_node(node, context)
        elsif node.is_a?(ORB::AST::PrivateCommentNode)
          transform_private_comment_node(node, context)
        elsif node.is_a?(ORB::AST::NewlineNode)
          transform_newline_node(node, context)
        elsif node.is_a?(ORB::Error)
          runtime_error(node)
        else
          raise ORB::CompilerError, "Unknown node type: #{node.class} for #{node.inspect}"
        end
      end
      # rubocop:enable Metrics/CyclomaticComplexity
      # rubocop:enable Metrics/PerceivedComplexity

      # Compile the children of a node and collect the result into a Temple expression
      def transform_children(node, context)
        [:multi, *node.children.map { |child| transform(child, context) }]
      end

      # Compile a TextNode into a Temple expression
      def transform_text_node(node, _context)
        [:static, node.text]
      end

      # Compile an PExpressionNode into a Temple expression
      def transform_printing_expression_node(node, context)
        if node.block?
          tmp = @identity.generate(:variable)
          [:multi,
            # Capture the result of the code in a variable. We can't do
            # `[:dynamic, code]` because it's probably not a complete
            # expression (which is a requirement for Temple).
            [
              :block, "#{tmp} = #{node.expression}",

              # Capture the content of a block in a separate buffer. This means
              # that `yield` will not output the content to the current buffer,
              # but rather return the output.
              #
              # The capturing can be disabled with the option :disable_capture.
              # Output code in the block writes directly to the output buffer then.
              # Rails handles this by replacing the output buffer for helpers.
              if @options.fetch(:disable_capture, false)
                transform_children(node, context)
              else
                [:capture, @identity.generate(:variable), transform_children(node, context)]
              end
            ],
            # Output the content.
            [:escape, true, [:dynamic, tmp]]]
        elsif node.children.any?
          [:multi, [:escape, true, [:dynamic, node.expression]], transform_children(node, context)]
        else
          [:escape, true, [:dynamic, node.expression]]
        end
      end

      # Compile an NPExpressionNode into a Temple expression
      def transform_control_expression_node(node, context)
        if node.block?
          tmp = @identity.generate(:variable)
          [:multi,
            [:block, "#{tmp} = #{node.expression}", transform_children(node, context)]]
        elsif node.children.any?
          [:multi, [:code, node.expression], transform_children(node, context)]
        else
          [:code, node.expression]
        end
      end

      # Compile an HTML TagNode into a Temple expression
      def transform_html_tag_node(node, context)
        [:orb, :tag, node.tag, node.attributes, transform_children(node, context)]
      end

      # Compile a component TagNode into a Temple expression
      def transform_component_tag_node(node, context)
        [:orb, :component, node, transform_children(node, context)]
      end

      # Compile a component slot TagNode into a Temple expression
      def transform_component_slot_tag_node(node, context)
        [:orb, :slot, node, transform_children(node, context)]
      end

      # Compile a block node into a Temple expression
      def transform_block_node(node, context)
        case node.name
        when :if
          [:orb, :if, node.expression, transform_children(node, context)]
        when :for
          [:orb, :for, node.expression, transform_children(node, context)]
        else
          [:static, 'Unknown block node']
        end
      end

      # Compile a comment node into a Temple expression
      def transform_public_comment_node(node, _context)
        [:html, :comment, [:static, node.text]]
      end

      # Compile a private_comment node into a Temple expression
      def transform_private_comment_node(_node, _context)
        [:static, ""]
      end

      # Compile a newline node into a Temple expression
      def transform_newline_node(_node, _context)
        [:newline]
      end

      # Compile a tag node with directives
      def transform_directives_for_tag_node(node, context)
        # First, process any :if directives
        if_directive = node.directives.fetch(:if, false)
        if if_directive
          node.remove_directive(:if)
          return [:if,
            if_directive,
            transform(node, context)]
        end

        # Second, process any :for directives
        for_directive = node.directives.fetch(:for, false)
        if for_directive
          node.remove_directive(:for)
          return [:orb, :for, for_directive, transform(node, context)]
        end

        # Last, render as a dynamic node expression
        transform(node, context)
      end

      # Compile a dynamic tag node
      def transform_dynamic_tag_node(node, context)
        [:orb, :dynamic, node, transform_children(node, context)]
      end

      # Helper or raising exceptions during compilation
      def runtime_error(error)
        [:multi].tap do |temple|
          (error.line - 1).times { temple << [:newline] } if error.line
          temple << [:code, %[raise ORB::Error.new(%q[#{error.message}], #{error.line.inspect})]]
        end
      end
    end
  end
end
