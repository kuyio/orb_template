## [Unreleased]

### Added

- `:unwrap` directive — conditionally strips a wrapper element while keeping its children. When the condition is true, only the children are rendered; when false, the element renders normally. Works on both HTML elements and components, and composes with `:if` and `:for`. (`lib/orb/temple/compiler.rb`, `lib/orb/temple/filters.rb`, `lib/orb/ast/tag_node.rb`)

### Fixed

- Fixed directive priority order: `:for` is now always outermost, followed by `:if`, then `:unwrap`. Previously, `:if` and `:unwrap` wrapped outside `:for`, which caused `NameError` at runtime when `:if` or `:unwrap` conditions referenced the loop variable (e.g., `<li :if={visible?(item)} :for="item in @items">`). (`lib/orb/temple/compiler.rb`)

### Changed

- Refactored `compiler_directives?` to use a `COMPILER_DIRECTIVES` constant set instead of chained `||` conditions, making it trivial to add future directives (`lib/orb/ast/tag_node.rb`)
- Refactored `transform_directives_for_tag_node` into `handle_if`, `handle_unwrap`, and `handle_for` helper methods, keeping the entry point as a single-line priority chain (`lib/orb/temple/compiler.rb`)
- Replaced `rails` gem with `railties`, `actionpack`, and `activemodel` in the test dummy app, removing unused frameworks (ActionCable, ActionText, ActiveStorage, ActionMailbox, ActionMailer, ActiveRecord) and reducing the dependency surface from 116 to 98 gems
- Added `make security` target running bundler-audit, brakeman, and trivy; integrated into the `make test` pipeline

## [0.2.4] - 2026-03-22

### Fixed

- Fixed `ORB::Temple::Engine: Option :capture_generator is invalid` — replaced separate `CaptureBuffer` class with `ORB::OutputBuffer` that uses `define_options` to register `capture_generator` as a valid option and conditionally returns `nil` from `return_buffer` when acting as a capture generator

## [0.2.3] - 2026-03-22

### Fixed

- Eliminated void-context warnings caused by Temple's `AttributeRemover` captures — added `CaptureBuffer` generator that returns `nil` from `return_buffer` instead of emitting a bare variable name

### Changed

- Benchmark tests are now excluded from the default `rake test` task and run separately via `rake benchmark`

## [0.2.2] - 2026-03-13

### Fixed

- Tuple destructuring in `:for` expressions now works correctly (e.g., `{#for name, spec in @tokens}`)

### Performance

- **33% faster** compilation pipeline for realistic templates, up to **52% faster** for expression-heavy templates
- Removed Temple `StaticAnalyzer` filter from engine pipeline -- ORB never emits static expressions as `:dynamic` nodes, so Ripper lexing/parsing on every dynamic node was pure overhead
- Boolean attributes now emit `[:static, ""]` directly instead of `[:dynamic, "nil"]`, avoiding unnecessary Ripper analysis
- Cached `block?`/`end?` regex results in expression node constructors (computed once instead of on every call)
- Optimized `Identity.generate` with direct string interpolation instead of array/compact/join
- Lazy-initialized `@errors` on AST nodes, saving one array allocation per node
- Removed unused `context={}` parameter from all compiler transform methods, eliminating hash allocation per recursive call
- Added single-pass `compile_captures_and_args` to `AttributesCompiler`, reducing double iteration over attributes
- Optimized `Token` constructor to avoid `method_missing` overhead and skip hash merge for common no-meta case
- Tokenizer: replaced per-call `StringScanner` allocation in `move_by` with `String#count`/`rindex`
- Tokenizer: switched from `StringIO` to `String` buffer with swap-on-consume pattern
- Tokenizer: added greedy multi-character scanning patterns for bulk text consumption in 9 tokenizer states

### Added

- Benchmark test suite (`test/benchmark_test.rb`) with 8 template categories, per-template regression thresholds, stage-level profiling, and Temple IR node count tracking

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
