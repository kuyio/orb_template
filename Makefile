# Makefile for ORB Ruby Gem

.PHONY: all test build clean install lint spec help

# Default target
all: test build

# Run test suite
spec:
	bundle exec rake test

# Build the gem
build:
	gem build orb_template.gemspec

# Deploy to RubyGems (requires authentication)
deploy: build
	gem push orb_template-*.gem

# Clean build artifacts
clean:
	rm -f *.gem

# Install the gem locally
install: build
	gem install orb_template-*.gem

# Run linting
lint:
	bundle exec rubocop

# Run both specs and linting
test: spec lint

# Show help
help:
	@echo "Available targets:"
	@echo "  all     - Run tests and build the gem (default)"
	@echo "  test    - Run both specs and linting"
	@echo "  build   - Build the gem package"
	@echo "  install - Build and install the gem locally"
	@echo "  clean   - Remove built gem files"
	@echo "  spec    - Run the test suite"
	@echo "  lint    - Run RuboCop linting"
	@echo "  help    - Show this help message"