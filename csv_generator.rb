require "csv"

class CsvGenerator
  def self.generate!(file_name:, header:, rows:)
    lead_time_column_index = header.find_index("lead_time")

    generated_csv = CSV.generate(headers: header, write_headers: true, encoding: Encoding::UTF_8) do |csv|
      rows.each do |row|
        converted_row = row.map.with_index do |value, idx|
          # lead_time は日で出力します
          next (value / 60 / 60 / 24).round(1) if idx == lead_time_column_index
          # Time 型の値は CSV で扱いやすい形にします
          next value.localtime.strftime("%Y-%m-%d %H:%M:%S") if value.is_a?(Time)

          value
        end
        csv << converted_row
      end
    end

    dir_name = File.dirname(file_name)
    Dir.mkdir(dir_name) unless Dir.exist?(dir_name)
    File.open(file_name, "w") { |file| file.write(generated_csv) }
  end
end
