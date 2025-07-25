# 0.2.0 (2025/25/07)

### Added
- Ruby 3.0+ performance optimizations
- Eval-based method generation for 2x faster hot path
- Version-specific implementation selection

### Changed  
- Significant performance improvements on Ruby 3.0+
- Internal RubyCapabilities module cleanup

### Performance
- Hot path: 1.1x overhead (vs 4.5x on Ruby 2.6)
- 50% faster method generation on Ruby 3+

## 0.1.2 (2025/11/07)

* Fix bug with missing yard documentation link

## 0.1.1 (2025/06/07)

* Added YARD configuration for automatic documentation generation
* Enhanced code comments for better API documentation

# 0.1.0 (2025/06/07)

* Initial public release