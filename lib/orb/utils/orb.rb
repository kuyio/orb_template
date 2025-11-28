# frozen_string_literal: true

module ORB
  module Utils
    class ORB
      def self.tokenize(source) # :nodoc:
        tokenizer = ::ORB::Tokenizer2.new(source)
        tokenizer.tokenize
      end
    end
  end
end
