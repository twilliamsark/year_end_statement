# How To Use CCYearEndStatement

`CCYearEndStatement` parses a Bank of America year-end summary PDF and the CSV files produced from that PDF.

This guide uses these example paths:

```text
/Users/todd/Documents/BoA_CC_YearEndSummary_2025.pdf
/Users/todd/Documents/BoA_CC_YearEndSummary_2025.csv
```

## Setup

Open `irb` with the gem loaded:

```bash
bundle exec irb -r cc_year_end_statement
```

You can also use the gem from a script with:

```ruby
require "cc_year_end_statement"
```

## Read A PDF

```ruby
path = "/Users/todd/Documents/BoA_CC_YearEndSummary_2025.pdf"

result = CCYearEndStatement::Extractor.call(filename: path)
```

The returned `result` is a `CCYearEndStatement::Extractor::Result` with these readers:

- `result.filename`
- `result.page_count`
- `result.categories`
- `result.transactions`

Example:

```ruby
result.filename
# => "/Users/todd/Documents/BoA_CC_YearEndSummary_2025.pdf"

result.page_count
# => 14
```

## Read Categories

`result.categories` returns an array of category objects.

```ruby
result.categories.map(&:name)
# => ["Merchandise", "Entertainment", "Health", "Travel and Transportation", "Services", "Education", "Utilities"]
```

Each category has:

- `name`
- `total`
- `subcategories`

Example:

```ruby
category = result.categories.first

category.name
# => "Merchandise"

category.total
# => 0.6469157e5

category.subcategories.map(&:name)
# => ["Clothing", "Department Store", ...]
```

## Read Subcategories

Each category contains subcategories.

```ruby
result.categories.each do |category|
  puts category.name

  category.subcategories.each do |subcategory|
    puts "  #{subcategory.name}: #{subcategory.total.to_s("F")}"
  end
end
```

Each subcategory has:

- `name`
- `total`
- `transactions`

Example lookup:

```ruby
travel = result.categories.find { |category| category.name == "Travel and Transportation" }
hotels = travel.subcategories.find { |subcategory| subcategory.name == "Hotels" }

hotels.total.to_s("F")
# => "100.0"
```

## Read Transactions

There are two ways to access transactions.

### 1. By subcategory

```ruby
travel = result.categories.find { |category| category.name == "Travel and Transportation" }
airline = travel.subcategories.find { |subcategory| subcategory.name == "Airline" }

airline.transactions.each do |transaction|
  puts [
    transaction.date,
    transaction.description,
    transaction.location,
    transaction.amount.to_s("F")
  ].join(" | ")
end
```

### 2. As one flat list

`result.transactions` flattens all category/subcategory transactions into one array and preserves the category and subcategory names on each transaction.

```ruby
result.transactions.first
# => #<data CCYearEndStatement::Extractor::Transaction
#      date=...,
#      description="...",
#      location="...",
#      amount=...,
#      category="Merchandise",
#      subcategory="Clothing">
```

Example:

```ruby
result.transactions.each do |transaction|
  puts [
    transaction.date,
    transaction.category,
    transaction.subcategory,
    transaction.description,
    transaction.location,
    transaction.amount.to_s("F")
  ].join(" | ")
end
```

## Spend Per Category

The extractor already captures the category total, so the simplest way is:

```ruby
result.categories.each do |category|
  puts "#{category.name}: #{category.total.to_s("F")}"
end
```

If you want a hash:

```ruby
spend_per_category = result.categories.to_h do |category|
  [category.name, category.total]
end

spend_per_category.transform_values { |amount| amount.to_s("F") }
```

You can also compute category totals from the flat transaction list:

```ruby
spend_per_category = result.transactions.group_by(&:category).transform_values do |transactions|
  transactions.sum(&:amount)
end
```

## Spend Per Subcategory

If you want totals grouped under each category:

```ruby
spend_per_subcategory = result.categories.to_h do |category|
  [
    category.name,
    category.subcategories.to_h do |subcategory|
      [subcategory.name, subcategory.total]
    end
  ]
end
```

If you want a flat hash keyed by both category and subcategory:

```ruby
spend_per_subcategory = result.transactions.group_by { |transaction| [transaction.category, transaction.subcategory] }.transform_values do |transactions|
  transactions.sum(&:amount)
end

spend_per_subcategory.each do |(category, subcategory), amount|
  puts "#{category} / #{subcategory}: #{amount.to_s("F")}"
end
```

## Write Transactions To CSV

`CCYearEndStatement::CSVWriter` uses `CCYearEndStatement::Extractor` internally and writes the flat transaction list to a delimited file.

By default it writes a pipe-delimited file next to the source PDF.

```ruby
path = "/Users/todd/Documents/BoA_CC_YearEndSummary_2025.pdf"

output_path = CCYearEndStatement::CSVWriter.call(filename: path)

output_path
# => "/Users/todd/Documents/BoA_CC_YearEndSummary_2025.csv"
```

The output includes these headers:

- `date`
- `category`
- `subcategory`
- `description`
- `location`
- `amount`

To use a different separator or output path:

```ruby
CCYearEndStatement::CSVWriter.call(
  filename: path,
  output_filename: "/Users/todd/Documents/year_end_transactions.csv",
  field_separator: ","
)
```

## Read Transactions From CSV

`CCYearEndStatement::CSVExtractor` reads a delimited file created by `CCYearEndStatement::CSVWriter` and rebuilds the same structured category, subcategory, and transaction result.

It auto-detects the delimiter from the CSV header row for files written by `CCYearEndStatement::CSVWriter`. If detection is not enough for a custom file, you can still pass `field_separator` explicitly.

```ruby
path = "/Users/todd/Documents/year_end_transactions.csv"

result = CCYearEndStatement::CSVExtractor.call(filename: path)

result.categories.map(&:name)
# => ["Merchandise", "Entertainment", ...]
```

The returned object is the same `CCYearEndStatement::Extractor::Result` shape, so `result.categories`, `result.transactions`, category totals, and subcategory totals all work the same way as the PDF extractor.

If the CSV uses a different separator, pass it explicitly:

```ruby
result = CCYearEndStatement::CSVExtractor.call(
  filename: "/Users/todd/Documents/year_end_transactions.csv",
  field_separator: ","
)
```

## Credits And Refunds

Credits are returned as negative amounts.

For example, a line ending in `CR` in the PDF becomes a negative `amount` in the parsed transaction.

That means transaction sums already reflect refunds or credits correctly:

```ruby
result.transactions.select { |transaction| transaction.amount < 0 }
```

## Error Cases

If `filename` is missing or blank, the extractors raise `ArgumentError`.

```ruby
CCYearEndStatement::Extractor.call(filename: nil)
CCYearEndStatement::CSVExtractor.call(filename: nil)
```

If the file does not exist, they raise `Errno::ENOENT`.

```ruby
CCYearEndStatement::Extractor.call(filename: "/tmp/missing.pdf")
CCYearEndStatement::CSVExtractor.call(filename: "/tmp/missing.csv")
```

## One-Shot Script Example

You can run the extractor without opening an interactive console:

```bash
bundle exec ruby -Ilib -r cc_year_end_statement -e '
path = "/Users/todd/Documents/BoA_CC_YearEndSummary_2025.pdf"
result = CCYearEndStatement::Extractor.call(filename: path)

puts "File: #{result.filename}"
puts "Pages: #{result.page_count}"
puts
puts "Spend per category:"

result.categories.each do |category|
  puts "- #{category.name}: #{category.total.to_s("F")}"
end
'
```
