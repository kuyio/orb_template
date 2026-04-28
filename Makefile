# Makefile for ORB Ruby Gem

.PHONY: all test build clean install lint spec benchmark security help

# Default target
all: test build

# Run test suite (excludes benchmarks)
spec:
	bundle exec rake test

# Run benchmark suite
benchmark:
	bundle exec rake benchmark

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

# Security scanning (dependency audit, static analysis, filesystem scan)
security:
	bundle exec bundle-audit check --update
	bundle exec brakeman --no-pager -q -p test/dummy
	trivy fs --scanners vuln,secret,misconfig .

# Run specs, linting, security, and benchmarks
test: spec lint security benchmark

# Show help
help:
	@echo "Available targets:"
	@echo "  all     - Run tests and build the gem (default)"
	@echo "  test    - Run both specs and linting"
	@echo "  build   - Build the gem package"
	@echo "  install - Build and install the gem locally"
	@echo "  clean   - Remove built gem files"
	@echo "  spec      - Run the test suite (excludes benchmarks)"
	@echo "  benchmark - Run the benchmark suite"
	@echo "  lint      - Run RuboCop linting"
	@echo "  security  - Run security scans (bundler-audit, brakeman, trivy)"
	@echo "  help      - Show this help message"