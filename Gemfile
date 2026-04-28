# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "irb"
gem "rake", "~> 13.0"
gem "rspec", "~> 3.0"

group :development do
  gem 'ruby-lsp'
end

group :development, :test do
  gem 'railties'
  gem 'actionpack'
  gem 'activemodel'
  gem "puma"
  gem 'listen'
  gem "sprockets-rails"
  gem "turbo-rails", "~> 1.5"
  gem "importmap-rails", "~> 2.0"
  gem 'benchmark'
  gem 'minitest'
  gem 'minitest-rails'
  gem 'view_component'
  gem 'slim-rails'
  gem 'haml-rails'
  gem 'kuyio-rubocop', github: 'kuyio/kuyio-rubocop'
  gem 'bundler-audit', require: false
  gem 'brakeman', require: false
end
