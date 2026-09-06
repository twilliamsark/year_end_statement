# frozen_string_literal: true

require "test_helper"

class YearEndStatementsCSVExtractorTest < Minitest::Test
  FakeExtractor = Struct.new(:result) do
    def call(filename:)
      raise ArgumentError, "filename is required" if filename.nil? || filename.to_s.strip.empty?

      result
    end
  end

  def test_requires_a_filename
    error = assert_raises(ArgumentError) do
      YearEndStatements::CSVExtractor.call(filename: nil)
    end

    assert_match(/filename is required/i, error.message)
  end

  def test_raises_when_the_csv_file_is_missing
    assert_raises(Errno::ENOENT) do
      YearEndStatements::CSVExtractor.call(filename: "/tmp/missing-year-end-summary.csv")
    end
  end

  def test_rebuilds_categories_subcategories_and_transactions_from_a_pipe_delimited_csv
    Dir.mktmpdir do |dir|
      path = File.join(dir, "year_end_transactions.csv")
      File.write(path, <<~CSV)
        date|category|subcategory|description|location|amount
        2025-07-01|Merchandise|Clothing|MENS WAREHOUSE 1534|JONESBORO, AR|740.61
        2025-07-08|Merchandise|Clothing|MENS WAREHOUSE 1534|JONESBORO, AR|249.08
        2025-07-23|Merchandise|Department Store|DILLARDS 406 TURTLE CR|JONESBORO, AR|179.03
        2025-05-09|Travel and Transportation|Hotels|COMFORT INNS|ORLANDO, FL|-100.0
      CSV

      result = YearEndStatements::CSVExtractor.call(filename: path)

      assert_equal path, result.filename
      assert_nil result.page_count
      assert_equal ["Merchandise", "Travel and Transportation"], result.categories.map(&:name)

      merchandise = result.categories.first
      assert_equal BigDecimal("1168.72"), merchandise.total
      assert_equal ["Clothing", "Department Store"], merchandise.subcategories.map(&:name)
      assert_equal BigDecimal("989.69"), merchandise.subcategories.first.total

      hotels = result.categories.last.subcategories.first
      assert_equal BigDecimal("-100.0"), hotels.total
      assert_equal Date.new(2025, 5, 9), hotels.transactions.first.date
      assert_equal "COMFORT INNS", hotels.transactions.first.description
      assert_equal "ORLANDO, FL", hotels.transactions.first.location
      assert_equal BigDecimal("-100.0"), hotels.transactions.first.amount

      assert_equal 4, result.transactions.size
      assert_equal BigDecimal("1068.72"), result.transactions.sum(&:amount)
    end
  end

  def test_reads_a_csv_with_a_custom_separator
    Dir.mktmpdir do |dir|
      path = File.join(dir, "year_end_transactions.csv")
      File.write(path, <<~CSV)
        date,category,subcategory,description,location,amount
        2025-11-12,Education,Education,UDEMY ONLINE COURSES,"UDEMY.COM, CA",30.36
      CSV

      result = YearEndStatements::CSVExtractor.call(filename: path, field_separator: ",")

      assert_equal ["Education"], result.categories.map(&:name)
      assert_equal BigDecimal("30.36"), result.categories.first.total
      assert_equal "Education", result.categories.first.subcategories.first.name
      assert_equal "UDEMY.COM, CA", result.transactions.first.location
    end
  end

  def test_auto_detects_a_comma_separated_csv_when_no_separator_is_passed
    Dir.mktmpdir do |dir|
      path = File.join(dir, "year_end_transactions.csv")
      File.write(path, <<~CSV)
        date,category,subcategory,description,location,amount
        2025-11-12,Education,Education,UDEMY ONLINE COURSES,"UDEMY.COM, CA",30.36
      CSV

      result = YearEndStatements::CSVExtractor.call(filename: path)

      assert_equal ["Education"], result.categories.map(&:name)
      assert_equal BigDecimal("30.36"), result.transactions.first.amount
      assert_equal "UDEMY.COM, CA", result.transactions.first.location
    end
  end

  def test_rejects_csv_files_with_unexpected_headers
    Dir.mktmpdir do |dir|
      path = File.join(dir, "year_end_transactions.csv")
      File.write(path, <<~CSV)
        posted_on|category|subcategory|description|location|amount
        2025-11-12|Education|Education|UDEMY ONLINE COURSES|UDEMY.COM, CA|30.36
      CSV

      error = assert_raises(ArgumentError) do
        YearEndStatements::CSVExtractor.call(filename: path)
      end

      assert_match(/unexpected CSV headers/i, error.message)
    end
  end

  def test_round_trips_the_output_generated_by_csv_writer
    Dir.mktmpdir do |dir|
      source_path = File.join(dir, "statement.pdf")
      File.write(source_path, "pdf")

      csv_path = YearEndStatements::CSVWriter.call(
        filename: source_path,
        extractor: FakeExtractor.new(extractor_result)
      )

      result = YearEndStatements::CSVExtractor.call(filename: csv_path)

      assert_equal extractor_result.transactions, result.transactions
      assert_equal extractor_result.categories.map(&:name), result.categories.map(&:name)
      assert_equal extractor_result.categories.map(&:total), result.categories.map(&:total)
    end
  end

  private

  def extractor_result
    YearEndStatements::Extractor::Result.new(
      filename: "/tmp/statement.pdf",
      page_count: 1,
      categories: [
        YearEndStatements::Extractor::Category.new(
          name: "Merchandise",
          total: BigDecimal("740.61"),
          subcategories: [
            YearEndStatements::Extractor::Subcategory.new(
              name: "Clothing",
              total: BigDecimal("740.61"),
              transactions: [
                YearEndStatements::Extractor::Transaction.new(
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
        YearEndStatements::Extractor::Category.new(
          name: "Travel and Transportation",
          total: BigDecimal("-100.0"),
          subcategories: [
            YearEndStatements::Extractor::Subcategory.new(
              name: "Hotels",
              total: BigDecimal("-100.0"),
              transactions: [
                YearEndStatements::Extractor::Transaction.new(
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