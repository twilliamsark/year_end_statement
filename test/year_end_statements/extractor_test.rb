# frozen_string_literal: true

require "test_helper"

class YearEndStatementsExtractorTest < Minitest::Test
  FakePage = Struct.new(:text)
  FakeReader = Struct.new(:page_count, :pages)

  SAMPLE_PAGES = [
    "Page 1 of 3\nAccount snapshot\n$64,691.57\nMerchandise\n",
    <<~PAGE,
      Page 2 of 3

      Preparing your taxes
      Here is a list of all your transactions between January 1, 2025 and December 31, 2025.

                  Merchandise $1,268.72
                   Clothing $1,089.69

                  Date         Description                    Location                                 Amount
                  07/01/25     MENS WAREHOUSE 1534            JONESBORO, AR                            740.61
                  07/08/25     MENS WAREHOUSE 1534            JONESBORO, AR                            249.08
                  12/22/25     SP HONEY HOPE BOUTIQ           187-09265814, AR                         100.00
                                                                                                $1,089.69
                   Department Store   $179.03

                  Date         Description                    Location                                 Amount
                  07/23/25     DILLARDS 406 TURTLE CR         JONESBORO, AR                            179.03
                                                                                                  $179.03
    PAGE
    <<~PAGE
      Page 3 of 3
                  Continued

      For travel deductions, search            Travel and Transportation $250.00
      "Topic 511" at www.irs.gov
                                               Hotels  $100.00

                                               Date         Description                    Location                                 Amount
                                               05/09/25     COMFORT INNS                   ORLANDO, FL                              100.00CR
                                                                                                                             $100.00
                   Airline$150.00

                  Date         Description                    Location                                 Amount
                  05/05/25     SWA*HVY BAG                    800-435-9792, TX                         150.00
                                                                                                  $150.00
                  Education
                  Education   $30.36

                  Date         Description                    Location                                 Amount
                  11/12/25     UDEMY ONLINE COURSES           UDEMY.COM, CA                              30.36
                                                                                                    $30.36
    PAGE
  ].freeze

  def test_requires_a_settable_filename
    error = assert_raises(ArgumentError) do
      YearEndStatements::Extractor.call(filename: nil, reader: fake_reader)
    end

    assert_match(/filename is required/i, error.message)
  end

  def test_raises_when_the_pdf_file_is_missing
    assert_raises(Errno::ENOENT) do
      YearEndStatements::Extractor.call(filename: "/tmp/missing-year-end-summary.pdf")
    end
  end

  def test_extracts_categories_subcategories_and_transactions_from_a_year_end_statement
    result = YearEndStatements::Extractor.call(
      filename: "/statements/BoA_CC_YearEndSummary_2025.pdf",
      reader: fake_reader
    )

    assert_equal "/statements/BoA_CC_YearEndSummary_2025.pdf", result.filename
    assert_equal 3, result.page_count
    assert_equal ["Merchandise", "Travel and Transportation", "Education"], result.categories.map(&:name)
    assert_equal ["Clothing", "Department Store"], result.categories.first.subcategories.map(&:name)

    clothing = result.categories.first.subcategories.first
    assert_equal BigDecimal("1089.69"), clothing.total
    assert_equal 3, clothing.transactions.size
    assert_equal Date.new(2025, 7, 1), clothing.transactions.first.date
    assert_equal "MENS WAREHOUSE 1534", clothing.transactions.first.description
    assert_equal "JONESBORO, AR", clothing.transactions.first.location
    assert_equal BigDecimal("740.61"), clothing.transactions.first.amount
    assert_equal "Merchandise", clothing.transactions.first.category
    assert_equal "Clothing", clothing.transactions.first.subcategory
  end

  def test_keeps_category_context_across_continued_pages_and_handles_credits_and_missing_spaces
    result = extract_sample
    travel = result.categories.find { |category| category.name == "Travel and Transportation" }

    assert_equal BigDecimal("250.00"), travel.total
    assert_equal ["Hotels", "Airline"], travel.subcategories.map(&:name)
    assert_equal BigDecimal("-100.00"), travel.subcategories.first.transactions.first.amount
    assert_equal BigDecimal("150.00"), travel.subcategories.last.total
    assert_equal "SWA*HVY BAG", travel.subcategories.last.transactions.first.description
  end

  def test_treats_a_repeated_category_heading_as_a_subcategory
    result = extract_sample
    education = result.categories.find { |category| category.name == "Education" }

    assert_equal ["Education"], education.subcategories.map(&:name)
    assert_equal BigDecimal("30.36"), education.subcategories.first.transactions.first.amount
  end

  def test_returns_a_flat_transaction_list_with_category_and_subcategory_names
    result = extract_sample

    assert_equal 7, result.transactions.size
    assert_equal ["Merchandise", "Merchandise", "Merchandise", "Merchandise", "Travel and Transportation", "Travel and Transportation", "Education"].uniq.sort,
                 result.transactions.map(&:category).uniq.sort
  end

  def test_extracts_the_bank_of_america_year_end_summary_when_the_session_file_is_present
    path = "/Users/todd/Documents/BoA_CC_YearEndSummary_2025.pdf"
    skip "Year-end summary PDF is not available at #{path}" unless File.exist?(path)

    result = YearEndStatements::Extractor.call(filename: path)

    assert_equal path, result.filename
    assert_equal 14, result.page_count
    assert_equal(
      ["Merchandise", "Entertainment", "Health", "Travel and Transportation", "Services", "Education", "Utilities"],
      result.categories.map(&:name)
    )
    assert_includes result.categories.first.subcategories.map(&:name), "Clothing"
    assert_operator result.transactions.size, :>, 100
    assert_equal BigDecimal("64691.57"), result.transactions.sum(&:amount)
  end

  private

  def extract_sample
    YearEndStatements::Extractor.call(
      filename: "BoA_CC_YearEndSummary_2025.pdf",
      reader: fake_reader
    )
  end

  def fake_reader
    FakeReader.new(SAMPLE_PAGES.size, SAMPLE_PAGES.map { |text| FakePage.new(text) })
  end
end
