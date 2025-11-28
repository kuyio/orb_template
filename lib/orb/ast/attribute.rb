# frozen_string_literal: true

module ORB
  module AST
    class Attribute
      attr_reader :name, :type

      def initialize(name, type = :str, value = nil)
        @name = name
        @type = type
        @value = value
      end

      def value
        if @type == :bool || @type == :boolean
          true
        else
          @value
        end
      end

      def bool?
        @type == :bool || @type == :boolean
      end

      def expression?
        @type == :expr || @type == :expression
      end

      def string?
        @type == :str || @type == :string
      end

      def splat?
        @type == :splat
      end

      def static?
        string? || bool?
      end

      def dynamic?
        expression?
      end

      def directive?
        @name&.start_with?(":")
      end
    end
  end
end
