# frozen_string_literal: true

module ORB
  class Railtie < ::Rails::Railtie
    initializer :orb_template, before: :load_config_initializers do
      require 'orb/rails_template'
    end
  end
end
