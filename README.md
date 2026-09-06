# YearEndStatements

`YearEndStatements` parses Bank of America year-end summary PDFs and CSV exports into a structured Ruby result.

The gem provides:

- `YearEndStatements::Extractor` for PDFs
- `YearEndStatements::CSVWriter` for writing flat transaction CSV files
- `YearEndStatements::CSVExtractor` for rebuilding structured results from CSV files

## Installation

Add the gem to your application:

```ruby
gem "year_end_statements", path: "/path/to/year_end_statements"
```

Or install it directly after building:

```bash
gem build year_end_statements.gemspec
gem install year_end_statements-0.1.0.gem
```

## Quick Start

```ruby
require "year_end_statements"

result = YearEndStatements::Extractor.call(
  filename: "/Users/todd/Documents/BoA_CC_YearEndSummary_2025.pdf"
)

puts result.categories.map(&:name)
puts result.transactions.size
```

Detailed usage examples are in `HOW_TO.md`.
