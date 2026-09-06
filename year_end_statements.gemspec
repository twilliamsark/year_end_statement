# frozen_string_literal: true

require_relative "lib/year_end_statements/version"

Gem::Specification.new do |spec|
  spec.name = "year_end_statements"
  spec.version = YearEndStatements::VERSION
  spec.authors = ["Todd"]

  spec.summary = "Parse Bank of America year-end summary PDFs and CSV files"
  spec.description = "Extract category, subcategory, and transaction data from Bank of America year-end summary PDFs and CSV exports."
  spec.homepage = "https://github.com/twilliamsark/year_end_statement/blob/main/HOW_TO.md"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"

  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*.rb", "test/**/*_test.rb", "README.md", "HOW_TO.md", "Rakefile"]
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "csv"
  spec.add_dependency "pdf-reader"

  spec.add_development_dependency "minitest"
  spec.add_development_dependency "rake"
end
