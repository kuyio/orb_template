# frozen_string_literal: true

module ORB
  module Temple
    extend ActiveSupport::Autoload

    autoload :Filters
    autoload :ComponentFilter
    autoload :AttributesCompiler
    autoload :Parser
    autoload :Compiler
    autoload :Identity
    autoload :Engine
    autoload :Generator, 'orb/temple/generators'
  end
end
