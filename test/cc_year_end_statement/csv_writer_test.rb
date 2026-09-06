# frozen_string_literal: true

require "test_helper"

class CCYearEndStatementCSVWriterTest < Minitest::Test
  FakeExtractor = Struct.new(:result) do
    def call(filename:)
      raise ArgumentError, "filename is required" if filename.nil? || filename.to_s.strip.empty?

      result
    end
  end

  def test_writes_transactions_to_a_pipe_delimited_csv_next_to_the_source_file_by_default
    Dir.mktmpdir do |dir|
      source_path = File.join(dir, "statement.pdf")
      File.write(source_path, "pdf")

      output_path = CCYearEndStatement::CSVWriter.call(
        filename: source_path,
        extractor: FakeExtractor.new(extractor_result)
      )

      assert_equal File.join(dir, "statement.csv"), output_path
      assert_equal <<~CSV, File.read(output_path)
        date|category|subcategory|description|location|amount
        2025-07-01|Merchandise|Clothing|MENS WAREHOUSE 1534|JONESBORO, AR|740.61
        2025-05-09|Travel and Transportation|Hotels|COMFORT INNS|ORLANDO, FL|-100.0
      CSV
    end
  end

  def test_writes_transactions_using_a_custom_separator_and_output_path
    Dir.mktmpdir do |dir|
      source_path = File.join(dir, "statement.pdf")
      output_path = File.join(dir, "transactions.txt")
      File.write(source_path, "pdf")

      returned_path = CCYearEndStatement::CSVWriter.call(
        filename: source_path,
        output_filename: output_path,
        field_separator: ",",
        extractor: FakeExtractor.new(extractor_result)
      )

      assert_equal output_path, returned_path
      assert_equal <<~CSV, File.read(output_path)
        date,category,subcategory,description,location,amount
        2025-07-01,Merchandise,Clothing,MENS WAREHOUSE 1534,"JONESBORO, AR",740.61
        2025-05-09,Travel and Transportation,Hotels,COMFORT INNS,"ORLANDO, FL",-100.0
      CSV
    end
  end

  private

  def extractor_result
    CCYearEndStatement::Extractor::Result.new(
      filename: "/tmp/statement.pdf",
      page_count: 1,
      categories: [
        CCYearEndStatement::Extractor::Category.new(
          name: "Merchandise",
          total: BigDecimal("740.61"),
          subcategories: [
            CCYearEndStatement::Extractor::Subcategory.new(
              name: "Clothing",
              total: BigDecimal("740.61"),
              transactions: [
                CCYearEndStatement::Extractor::Transaction.new(
                  date: Date.new(2025, 7, 1),
                  description: "MENS WAREHOUSE 1534",
                  location: "JONESBORO, AR",
                  amount: BigDecimal("740.61"),
                  category: "Merchandise",
                  subcategory: "Clothing"
                )
              ]
            )
          ]
        ),
        CCYearEndStatement::Extractor::Category.new(
          name: "Travel and Transportation",
          total: BigDecimal("-100.0"),
          subcategories: [
            CCYearEndStatement::Extractor::Subcategory.new(
              name: "Hotels",
              total: BigDecimal("-100.0"),
              transactions: [
                CCYearEndStatement::Extractor::Transaction.new(
                  date: Date.new(2025, 5, 9),
                  description: "COMFORT INNS",
                  location: "ORLANDO, FL",
                  amount: BigDecimal("-100.0"),
                  category: "Travel and Transportation",
                  subcategory: "Hotels"
                )
              ]
            )
          ]
        )
      ]
    )
  end
end
