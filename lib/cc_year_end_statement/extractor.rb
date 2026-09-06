# frozen_string_literal: true

module CCYearEndStatement
  class Extractor
    Result = Data.define(:filename, :page_count, :categories) do
      def transactions
        categories.flat_map do |category|
          category.subcategories.flat_map do |subcategory|
            subcategory.transactions.map do |transaction|
              transaction.with(category: category.name, subcategory: subcategory.name)
            end
          end
        end
      end
    end

    Category = Data.define(:name, :total, :subcategories)
    Subcategory = Data.define(:name, :total, :transactions)
    Transaction = Data.define(:date, :description, :location, :amount, :category, :subcategory)

    KNOWN_CATEGORIES = [
      "Merchandise",
      "Entertainment",
      "Health",
      "Travel and Transportation",
      "Services",
      "Education",
      "Utilities"
    ].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(filename:, reader: nil)
      @filename = filename
      @reader = reader
    end

    def call
      raise ArgumentError, "filename is required" if missing_value?(filename)
      raise Errno::ENOENT, filename unless reader || File.exist?(filename)

      pdf = reader || PDF::Reader.new(filename)
      categories = Parser.new(pdf.pages.map(&:text)).parse

      Result.new(filename: filename, page_count: pdf.page_count, categories: categories)
    end

    private

    attr_reader :filename, :reader

    def missing_value?(value)
      value.nil? || value.to_s.strip.empty?
    end

    class Parser
      HEADING = /
        \A
        (?:.*?\s{2,})?
        (?<name>[A-Za-z][A-Za-z0-9 &\/\-']*?)
        \s*
        \$(?<amount>[\d,]+\.\d{2})
        \s*
        \z
      /x
      NAME_ONLY = /\A(?<name>[A-Za-z][A-Za-z0-9 &\/\-']+)\s*\z/
      TOTAL_ONLY = /\A\$(?<amount>[\d,]+\.\d{2})\s*\z/
      TRANSACTION = /
        \A
        (?<date>\d{2}\/\d{2}\/\d{2})
        \s+
        (?<description>.+?)
        \s{2,}
        (?<location>.+?)
        \s+
        (?<amount>[\d,]+\.\d{2})(?<credit>CR)?
        \s*
        \z
      /x

      def initialize(pages_text)
        @pages_text = pages_text
        @categories = []
        @current_category = nil
        @current_subcategory = nil
        @in_transaction_list = false
      end

      def parse
        pages_text.each { |page_text| parse_page(page_text) }
        finalize_subcategory
        finalize_category
        categories
      end

      private

      attr_reader :pages_text, :categories
      attr_accessor :current_category, :current_subcategory, :in_transaction_list

      def parse_page(page_text)
        page_text.each_line do |raw_line|
          line = normalize(raw_line)
          next if line.empty?

          @in_transaction_list = true if line.match?(/Preparing your taxes/i)
          next unless in_transaction_list
          next if skip?(line)

          if (match = line.match(TRANSACTION))
            record_transaction(match)
          elsif (match = line.match(TOTAL_ONLY))
            close_subcategory_with(parse_amount(match[:amount]))
          elsif (match = line.match(HEADING))
            record_heading(match[:name], parse_amount(match[:amount]))
          elsif (match = line.match(NAME_ONLY)) && known_category?(match[:name])
            start_category(match[:name], nil)
          end
        end
      end

      def normalize(raw_line)
        line = raw_line.to_s.sub(/([A-Za-z])\$/, '\1 $').strip
        extract_right_column(line)
      end

      def extract_right_column(line)
        if (match = line.match(/\A(?:For |expenses|related |"Topic|www\.).*?\s{2,}(.+)\z/i))
          return match[1].strip
        end

        if (match = line.match(/\A(.+?)\s{2,}([A-Za-z].*\$[\d,]+\.\d{2})\s*\z/)) && !match[1].match?(/\A\d{2}\/\d{2}\/\d{2}/)
          return match[2].strip
        end

        known = Regexp.union(KNOWN_CATEGORIES)
        if (match = line.match(/\s{2,}(#{known})\s*\z/))
          return match[1]
        end

        line
      end

      def skip?(line)
        line.match?(/\APage \d+ of \d+\z/i) ||
          line.match?(/\AContinued\z/i) ||
          line.match?(/\AOver, please\z/i) ||
          line.match?(/\ADate Description Location Amount\z/i) ||
          line.match?(/Written disputes must be sent/i) ||
          line.match?(/Year-End Summary does not extend/i) ||
          line.match?(/Thank you for your business/i) ||
          line.match?(/Bank of America/i) ||
          line.match?(/search "Topic/i) ||
          line.match?(/\Awww\.irs\.gov/i) ||
          line.match?(/Here is a list of all your transactions/i) ||
          line.match?(/Preparing your taxes/i)
      end

      def record_heading(name, amount)
        if known_category?(name) && current_category&.dig(:name) != name
          start_category(name, amount)
        else
          start_subcategory(name, amount)
        end
      end

      def start_category(name, amount)
        finalize_subcategory
        finalize_category
        self.current_category = { name: name, total: amount, subcategories: [] }
      end

      def start_subcategory(name, amount)
        raise "subcategory #{name.inspect} found before a category" unless current_category

        finalize_subcategory
        self.current_subcategory = { name: name, total: amount, transactions: [] }
      end

      def record_transaction(match)
        start_subcategory(current_category[:name], current_category[:total]) if current_subcategory.nil? && current_category

        amount = parse_amount(match[:amount])
        amount = -amount if match[:credit]

        current_subcategory[:transactions] << Transaction.new(
          date: Date.strptime(match[:date], "%m/%d/%y"),
          description: match[:description].strip,
          location: match[:location].strip,
          amount: amount,
          category: current_category[:name],
          subcategory: current_subcategory[:name]
        )
      end

      def close_subcategory_with(amount)
        return unless current_subcategory

        current_subcategory[:total] ||= amount
        finalize_subcategory
      end

      def finalize_subcategory
        return unless current_subcategory

        current_category[:subcategories] << Subcategory.new(**current_subcategory)
        self.current_subcategory = nil
      end

      def finalize_category
        return unless current_category

        current_category[:total] ||= current_category[:subcategories].sum(BigDecimal("0")) do |subcategory|
          subcategory.total || BigDecimal("0")
        end
        categories << Category.new(**current_category)
        self.current_category = nil
      end

      def known_category?(name)
        KNOWN_CATEGORIES.include?(name)
      end

      def parse_amount(value)
        BigDecimal(value.delete(","))
      end
    end
  end
end
