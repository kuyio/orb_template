## [Unreleased]

## [0.2.0] - 2026-03-12

### Security

- **CRITICAL**: Prevent code injection via `:for` directive by validating enumerator as a Ruby identifier and rejecting semicolons in collection expressions (`lib/orb/temple/filters.rb`)
- **HIGH**: Escape dynamic attribute expressions to prevent XSS via unescaped attribute values (`lib/orb/temple/attributes_compiler.rb`)
- **HIGH**: Validate `:with` directive values as valid Ruby identifiers to prevent code injection in component and slot blocks (`lib/orb/temple/filters.rb`)
- **HIGH**: Validate dynamic HTML tag names against a strict pattern to prevent code injection through crafted tag names (`lib/orb/temple/filters.rb`)
- **HIGH**: Validate component names as valid Ruby constant paths before interpolation into generated code (`lib/orb/temple/filters.rb`)
- **HIGH**: Validate slot names as valid Ruby identifiers before interpolation into `with_` method calls (`lib/orb/temple/filters.rb`)
- **MEDIUM**: Add maximum brace nesting depth (100) in tokenizer to prevent stack overflow / memory exhaustion from deeply nested expressions (`lib/orb/tokenizer2.rb`)
- **MEDIUM**: Use `String#inspect` instead of `%q[]` for error message interpolation to prevent delimiter escape attacks (`lib/orb/temple/compiler.rb`)
- **MEDIUM**: Restrict attribute name pattern to valid HTML attribute characters, preventing injection via malformed attribute names (`lib/orb/patterns.rb`)
- **LOW**: Add maximum template size limit (2MB) to prevent denial-of-service via oversized templates (`lib/orb/tokenizer2.rb`)

### Breaking Changes

- Component names are now validated against `VALID_COMPONENT_NAME` (`/\A[A-Z]\w*(::[A-Z]\w*)*\z/`). Components with non-standard names will raise `ORB::SyntaxError`.

### Documentation

- Added security analysis report (`docs/2026-03-12-security-analysis.md`)
- Updated README with security information

## [0.1.3] - 2026-02-06

### Fixed

- Components with splat attributes incorrectly rendering as plain HTML tags instead of the component

## [0.1.2] - 2026-01-30

### Added

- Support for splat expressions on HTML elements and components

### Changed

- Improved error display in the Rails web console

### Documentation

- Spelling and wording corrections in README
- Fixed code examples in README

## [0.1.1] - 2025-11-28

### Changed
- Removed dependency on ActiveSupport for improved lightweight usage
- Only load Railtie when running in Rails environment for better performance

### Fixed
- Corrected Editor plugin URLs in README
- Fixed gem name to use lowercase in gemspec

### Documentation
- Added demo video to README.md

## [0.1.0] - 2025-11-28

- Initial release of the ORB library.
