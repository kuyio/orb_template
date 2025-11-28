# frozen_string_literal: true

require 'temple'
require 'cgi/util'

require_relative "orb/errors"
require_relative "orb/token"
require_relative "orb/tokenizer"
require_relative "orb/tokenizer2"
require_relative "orb/render_context"
require_relative "orb/ast"
require_relative "orb/parser"
require_relative "orb/document"
require_relative "orb/template"
require_relative "orb/temple"
require_relative "orb/rails_template"

module ORB
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
