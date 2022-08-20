require "csv"

class CsvGenerator
  def self.generate!(file_name:, header:, rows:)
    generated_csv = CSV.generate(headers: header, write_headers: true, encoding: Encoding::UTF_8) do |csv|
      rows.each do |row|
        converted_row = row.map { _1.is_a?(Time) ? _1.localtime.strftime("%Y-%m-%d %H:%M:%S") : _1 }
        csv << converted_row
      end
    end

    dir_name = File.dirname(file_name)
    Dir.mkdir(dir_name) unless Dir.exist?(dir_name)
    File.open(file_name, "w") { |file| file.write(generated_csv) }
  end
end
