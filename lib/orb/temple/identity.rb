# frozen_string_literal: true

module ORB
  module Temple
    class Identity
      def initialize
        @unique_id = 0
      end

      def generate(prefix = nil)
        @unique_id += 1
        ["_orb_compiler", prefix, @unique_id].compact.join('_')
      end
    end
  end
end
