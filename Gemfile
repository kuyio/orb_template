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
  gem 'rails'
  gem "puma"
  gem 'listen'
  gem "sprockets-rails"
  gem "turbo-rails", "~> 1.5"
  gem "importmap-rails", "~> 2.0"
  gem 'minitest'
  gem 'minitest-rails'
  gem 'view_component'
  gem 'slim-rails'
  gem 'haml-rails'
  gem 'kuyio-rubocop', github: 'kuyio/kuyio-rubocop'
end
