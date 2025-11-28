# frozen_string_literal: true

require_relative "test_helper"

class ORBTest < ActiveSupport::TestCase
  def test_that_it_has_a_version_number
    assert_not_nil ::ORB::VERSION
  end

  def test_default_namespaces_is_set_by_initializer
    # as set in test/dummy/config/initializers/orb.rb
    assert_equal ::ORB.namespaces, %w[Demo]
  end

  def assert_cache_classes_is_set_to_default
    assert_true ::ORB.cache_classes
  end

  def test_html_escape
    assert_equal "&lt;script&gt;", ORB.html_escape("<script>")
  end
end
