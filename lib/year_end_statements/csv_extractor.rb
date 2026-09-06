# frozen_string_literal: true

module YearEndStatements
  class CSVExtractor
    SUPPORTED_FIELD_SEPARATORS = ["|", ",", "\t", ";"].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(filename:, field_separator: "|")
      @filename = filename
      @field_separator = field_separator
    end

    def call
      raise ArgumentError, "filename is required" if missing_value?(filename)
      raise Errno::ENOENT, filename unless File.exist?(filename)

      rows = CSV.read(filename, headers: true, col_sep: resolved_field_separator)
      validate_headers!(rows.headers)

      categories = build_categories(rows)
      Extractor::Result.new(filename: filename, page_count: nil, categories: categories)
    end

    private

    attr_reader :field_separator, :filename

    def build_categories(rows)
      grouped_categories = {}

      rows.each do |row|
        transaction = build_transaction(row)
        category = (grouped_categories[transaction.category] ||= { total: BigDecimal("0"), subcategories: {} })
        category[:total] += transaction.amount

        subcategory = (category[:subcategories][transaction.subcategory] ||= { total: BigDecimal("0"), transactions: [] })
        subcategory[:total] += transaction.amount
        subcategory[:transactions] << transaction
      end

      grouped_categories.map do |category_name, category_data|
        Extractor::Category.new(
          name: category_name,
          total: category_data[:total],
          subcategories: category_data[:subcategories].map do |subcategory_name, subcategory_data|
            Extractor::Subcategory.new(
              name: subcategory_name,
              total: subcategory_data[:total],
              transactions: subcategory_data[:transactions]
            )
          end
        )
      end
    end

    def build_transaction(row)
      Extractor::Transaction.new(
        date: Date.iso8601(row.fetch("date")),
        category: row.fetch("category"),
        subcategory: row.fetch("subcategory"),
        description: row.fetch("description"),
        location: row.fetch("location"),
        amount: BigDecimal(row.fetch("amount"))
      )
    end

    def resolved_field_separator
      sniffed_field_separator || field_separator
    end

    def sniffed_field_separator
      first_line = File.open(filename, &:readline)

      SUPPORTED_FIELD_SEPARATORS.find do |separator|
        first_line.delete_suffix("\n").delete_suffix("\r").split(separator) == CSVWriter::HEADERS
      end
    rescue EOFError
      nil
    end

    def validate_headers!(headers)
      return if headers == CSVWriter::HEADERS

      raise ArgumentError, "unexpected CSV headers: #{headers.inspect}"
    end

    def missing_value?(value)
      value.nil? || value.to_s.strip.empty?
    end
  end
end
