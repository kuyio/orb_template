# frozen_string_literal: true

module ORB
  module Utils
    class ERB
      def self.tokenize(source) # :nodoc:
        require "strscan"
        source = StringScanner.new(source.chomp)
        tokens = []

        start_re = /<%(?:={1,2}|-|\#|%)?/m
        finish_re = /(?:[-=])?%>/m

        until source.eos?
          pos = source.pos
          source.scan_until(/(?:#{start_re}|#{finish_re})/)
          len = source.pos - source.matched.bytesize - pos

          case source.matched
          when start_re
            tokens << [:TEXT, source.string[pos, len]] if len.positive?
            tokens << [:OPEN, source.matched]
            raise NotImplemented unless source.scan(/(.*?)(?=#{finish_re}|\z)/m)

            tokens << [:CODE, source.matched] unless source.matched.empty?
            tokens << [:CLOSE, source.scan(finish_re)] unless source.eos?

          when finish_re
            tokens << [:CODE, source.string[pos, len]] if len.positive?
            tokens << [:CLOSE, source.matched]
          else
            raise NotImplemented, source.matched
          end
        end

        tokens
      end
    end
  end
end
