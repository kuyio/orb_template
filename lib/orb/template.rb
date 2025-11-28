# frozen_string_literal: true

module ORB
  class Template
    attr_reader :doc

    class << self
      # create a new `Template` instance and parse the given source
      def parse(source, opts = {})
        template = Template.new(**opts)
        template.parse(source)
        template
      end
    end

    # Create a new `Template` instance. Use `Template.parse` instead.
    def initialize(**opts)
      @options = opts
    end

    # Parses the given `source` and returns `self` for chaining.
    def parse(source)
      @doc = Document.new(tokenize(source))
      self
    end

    # Local assigns
    def assigns
      @assigns ||= {}
    end

    # Parsing and rendering errors
    def errors
      @errors ||= []
    end

    # Render the template with the given `assigns`, which is a hash of local variables.
    def render(*args)
      # if we don't have a Document node, render to an empty string
      retun "" unless @doc

      # Determine the rendering context, which can either be a hash of local variables
      # or an instance of `ORB::RenderContext`.
      render_context = case args.first
                       when ORB::RenderContext
                         args.shift
                       when Hash
                         assigns.merge!(args.shift)
                         ORB::RenderContext.new(assigns)
                       when nil
                         ORB::RenderContext.new(assigns)
                       else
                         raise ArgumentError, "Expected a hash of local assigns or a ORB::RenderContext."
                       end

      # Render loop
      begin
        @doc.render(render_context)
      ensure
        @errors = render_context.errors
      end
    end

    private

    def tokenize(source)
      return [] if source.nil? || source.empty?

      ORB::Tokenizer2.new(source, **@options).tokenize!
    end
  end
end
