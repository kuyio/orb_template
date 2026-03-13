# frozen_string_literal: true

module ORB
  module Temple
    class Identity
      def initialize
        @unique_id = 0
      end

      def generate(prefix = nil)
        @unique_id += 1
        if prefix
          "_orb_compiler_#{prefix}_#{@unique_id}"
        else
          "_orb_compiler_#{@unique_id}"
        end
      end
    end
  end
end
