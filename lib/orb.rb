# frozen_string_literal: true

require 'temple'
require 'cgi/util'
require "active_support/dependencies/autoload"

module ORB
  extend ActiveSupport::Autoload

  autoload :Error, 'orb/errors'
  autoload :SyntaxError, 'orb/errors'
  autoload :ParserError, 'orb/errors'
  autoload :CompilerError, 'orb/errors'
  autoload :Token
  autoload :Tokenizer
  autoload :RenderContext
  autoload :AST
  autoload :Parser
  autoload :Document
  autoload :Template
  autoload :Temple
  autoload :RailsTemplate

  # Next-gen tokenizer built on top of strscan
  autoload :Tokenizer2

  # Configure class caching
  singleton_class.send(:attr_accessor, :cache_classes)
  self.cache_classes = true

  # Configure order of component namespace lookups
  singleton_class.send(:attr_accessor, :namespaces)
  self.namespaces = []

  def self.lookup_component(name)
    namespaces.each do |namespace|
      klass = "#{namespace}::#{name}"
      return klass if Object.const_defined?(klass)
    end

    nil
  end

  def self.html_escape(str)
    CGI.escapeHTML(str.to_s)
  end
end

# Load the Railtie if we are in a Rails environment
require 'orb/railtie' if defined?(Rails)
