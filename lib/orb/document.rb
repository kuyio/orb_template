# frozen_string_literal: true

module ORB
  class Document
    attr_reader :root

    def initialize(tokens)
      parse(tokens)
    end

    def parse(tokens)
      @root ||= Parser.parse(tokens)
    end

    def render(context)
      @root.render(context)
    end
  end
end
