# CCYearEndStatement

`CCYearEndStatement` parses Bank of America year-end summary PDFs and CSV exports into a structured Ruby result.

The gem provides:

- `CCYearEndStatement::Extractor` for PDFs
- `CCYearEndStatement::CSVWriter` for writing flat transaction CSV files
- `CCYearEndStatement::CSVExtractor` for rebuilding structured results from CSV files

## Installation

Add the gem to your application:

```ruby
gem "cc_year_end_statement", path: "/path/to/cc_year_end_statement"
```

Or install it directly after building:

```bash
gem build cc_year_end_statement.gemspec
gem install cc_year_end_statement-0.1.0.gem
```

## Quick Start

```ruby
require "cc_year_end_statement"

result = CCYearEndStatement::Extractor.call(
  filename: "/Users/todd/Documents/BoA_CC_YearEndSummary_2025.pdf"
)

puts result.categories.map(&:name)
puts result.transactions.size
```

Detailed usage examples are in `HOW_TO.md`.
