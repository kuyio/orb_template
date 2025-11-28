# frozen_string_literal: true

module ORB
  class RenderContext
    def initialize(assigns = {})
      @assigns = assigns
      @errors = []
    end

    def []=(key, value)
      @assigns[key] = value
    end

    def [](key)
      resolve(key)
    end

    def has_key?(key)
      resolve(key) != nil
    end

    attr_reader :errors

    def binding
      # rubocop:disable Style/OpenStructUse
      OpenStruct.new(@assigns).instance_eval { binding }
      # rubocop:enable Style/OpenStructUse
    end

    private

    def resolve(key)
      @assigns[key]
    end
  end
end
