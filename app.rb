require "date"

require "./github.rb"
require "./circleci.rb"
require "./csv_generator.rb"

REPO = ENV["REPO"]
today = Date.today
FROM = ENV["FROM"] ? Date.parse(ENV["FROM"]) : today - 14
TO = ENV["TO"] ? Date.parse(ENV["TO"]) : today

# @param seconds [Integer,Float]
# @return Float
def seconds_to_days(seconds)
  value = seconds.is_a?(Integer) ? seconds.to_f : seconds
  value / 60 / 60 / 24
end

# GitHub からメトリクスを取得します
github = Github.new(access_token: ENV["ACCESS_TOKEN"], repo: REPO)
total_lead_time = github.get_total_lead_time(from: FROM, to: TO)

# PR の情報を CSV 形式で保存します
header = Github::PullRequestStats.members.map(&:to_s)
rows = github.pr_stats_list.map(&:to_a)
CsvGenerator.generate!(file_name: "artifacts/#{REPO.split("/")[-1]}_#{FROM}_#{TO}.csv", header:, rows:)

# CircleCI からメトリクスを取得します
circleci = Circleci.new(access_token: ENV["CIRCLE_CI_PERSONAL_API_TOKEN"], repo: REPO)
staging_ci_duration_seconds = circleci.get_duration_metrics_median(branch: "staging")
master_ci_duration_seconds = circleci.get_duration_metrics_median(branch: "master")
staging_ci_duration_days = seconds_to_days(staging_ci_duration_seconds)
master_ci_duration_days = seconds_to_days(master_ci_duration_seconds)

# ここでは営業日を大まかに算出し計算に使います
# 1年の中で休日が120日、平日が245日。そこから 245 / 365 = 0.67 としています
# 計測期間が5日を超える場合は0.67掛けします
total_days = TO - FROM
business_days = (total_days > 5 ? total_days * 0.67 : total_days).to_i

total_change_count = github.pr_stats_list.size

puts
puts "[#{REPO}] #{FROM} 〜 #{TO}"
puts "総デプロイ回数: #{github.merged_into_master_issues.items.size}回"
puts "平均デプロイ回数: #{((github.merged_into_master_issues.items.size).to_f / (business_days).to_f).round(3)}回/日"
puts "総変更数: #{total_change_count}"
puts "変更リードタイム（CIを除く）: #{(total_lead_time / total_change_count).round(3)}日"
puts "変更リードタイム（CI）: staging #{staging_ci_duration_seconds}秒 production #{master_ci_duration_seconds}秒"
puts "変更リードタイム: #{(total_lead_time / total_change_count + staging_ci_duration_days + master_ci_duration_days).round(3)}日"
