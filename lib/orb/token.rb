# frozen_string_literal: true

module ORB
  # A simple PORO to represent a token.
  class Token
    attr_accessor :type, :value, :meta

    def initialize(type, value, meta = {})
      @type = type
      @value = value
      @meta = meta
      @line = line || 0
    end

    def set_meta(key, value)
      meta[key.to_sym] = value
    end

    def respond_to_missing?(method, _include_private = false)
      meta.has_key?(method.to_sym)
    end

    def method_missing(method, *args, &block)
      if meta.has_key?(method.to_sym)
        meta[method.to_sym]
      else
        super
      end
    end

    def ==(other)
      type == other.type &&
        value == other.value &&
        meta == other.meta
    end

    attr_reader :line

    def inspect
      to_s
    end

    def to_s
      "#<ORB::Token[#{type}] meta=#{meta.inspect} value=#{value.inspect}>"
    end
  end
end
