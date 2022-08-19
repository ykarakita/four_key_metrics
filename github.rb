require 'octokit'
require 'csv'

REPO = ENV["REPO"]
TIME_FORMAT = "%Y-%m-%d %H:%M:%S"

CREATED_FROM = "2022-01-01"
CREATED_TO = "2022-06-30"

PullRequestStats = Struct.new(:pr_number, :pr_title, :first_commit_datetime, :merged_into_staging_datetime, :merged_into_master_datetime, :first_commit_user_name, :lead_time, keyword_init: true)

def client
  Octokit::Client.new(access_token: ENV['ACCESS_TOKEN'], auto_paginate: true)
end

# @param datetime [Time]
# @return String
def format_datetime(datetime)
  datetime.localtime.strftime(TIME_FORMAT)
end

# @param seconds [Integer,Float]
# @return Float
def seconds_to_days(seconds)
  value = seconds.is_a?(Integer) ? seconds.to_f : seconds
  value / 60 / 60 / 24
end

puts "期間内に master にマージされたデプロイ PR 一覧を取得します"

# 期間内に master にマージされたデプロイ PR 一覧を取得
query = "repo:#{REPO} is:merged base:master merged:#{CREATED_FROM}..#{CREATED_TO}"
merged_into_master_issues = client.search_issues(query, per_page: 100)

pr_stats_list = []
merged_into_master_issues.items.each do |issue|
  printf "."
  merged_date = issue.pull_request.merged_at

  # デプロイ PR のコミット一覧から、計測対象の PR の number、 staging マージ日時を取得
  pull_request_number = issue.number
  commits = client.pull_request_commits(REPO, pull_request_number)

  commits.each do |commit|
    commit_message = commit.commit.message
    next if commit_message.include?("dependabot")

    pull_request_number = commit_message.slice(/Merge pull request #[0-9]*/)&.slice(/#[0-9]*/)&.gsub("#", "")
    next unless pull_request_number

    pr_stats_list << PullRequestStats.new(pr_number: pull_request_number,
                                          merged_into_staging_datetime: commit.commit.committer.date,
                                          merged_into_master_datetime: merged_date,
                                          pr_title: commit_message.split(/\n/).last)
  end
end

puts
puts "計測対象の PR の情報を取得します"

pr_stats_list.each do |pr_stats|
  printf "."
  # 計測対象の PR に紐づく commits を取得
  commits = client.pull_request_commits(REPO, pr_stats.pr_number)
  first_commit = commits.first.commit

  # 計測対象の PR タイトル、最初のコミット日時、PR 作成者を格納
  pr_stats.first_commit_datetime = first_commit.committer.date
  pr_stats.first_commit_user_name = first_commit.author.name
end

pr_stats_list.delete_if { _1.first_commit_user_name.include?("dependabot") }

# 各 PR のリードタイムを計測
pr_stats_list.each do |pr_stats|
  before_merge_into_staging_time = pr_stats.merged_into_staging_datetime - pr_stats.first_commit_datetime
  after_merged_into_staging_time = pr_stats.merged_into_master_datetime - pr_stats.merged_into_staging_datetime
  lead_time_sec = before_merge_into_staging_time + after_merged_into_staging_time
  pr_stats.lead_time = seconds_to_days(lead_time_sec).round(3)
end

header = PullRequestStats.members.map(&:to_s)
generated_csv = CSV.generate(headers: header, write_headers: true, encoding: Encoding::UTF_8) do |csv|
  pr_stats_list.each do |pr_stats|
    csv << pr_stats.map { _1.is_a?(Time) ? format_datetime(_1) : _1 }
  end
end

begin
  File.open("artifacts/#{REPO.split("/")[-1]}_#{CREATED_FROM}_#{CREATED_TO}.csv", "w") do |file|
    file.write(generated_csv)
  end
rescue Errno::ENOENT
  Dir.mkdir("artifacts")
  retry
end

total_lead_time = pr_stats_list.map(&:lead_time).sum

# ここでは営業日を大まかに算出し計算に使います
# 1年の中で休日が120日、平日が245日。そこから 245 / 365 = 0.67 としています
# 計測期間が5日を超える場合は0.67掛けします
total_days = seconds_to_days(Time.parse(CREATED_TO) - Time.parse(CREATED_FROM))
business_days = (total_days > 5 ? total_days * 0.67 : total_days).to_i

require "circleci"
require "uri"
require "net/http"
require "openssl"

def request_circleci_api(branch)
  endpoint = "https://circleci.com/api/v2/insights/gh/#{REPO}/workflows?branch=#{branch}&reporting-window=last-90-days"
  url = URI(endpoint)
  headers = { "Circle-Token" => ENV["CIRCLE_CI_PERSONAL_API_TOKEN"] }

  http = Net::HTTP.new(url.host, url.port)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE

  request = Net::HTTP::Get.new(url, headers)
  http.request(request)
end

staging_insights = request_circleci_api("staging")
master_insights = request_circleci_api("master")

staging_ci_duration_seconds = JSON.parse(staging_insights.read_body)["items"].size >= 1 ? JSON.parse(staging_insights.read_body)["items"][0]["metrics"]["duration_metrics"]["median"] : 0
master_ci_duration_seconds = JSON.parse(master_insights.read_body)["items"].size >= 1 ? JSON.parse(master_insights.read_body)["items"][0]["metrics"]["duration_metrics"]["median"] : 0

staging_ci_duration_days = seconds_to_days(staging_ci_duration_seconds)
master_ci_duration_days = seconds_to_days(master_ci_duration_seconds)

puts
puts "[#{REPO}] #{CREATED_FROM} 〜 #{CREATED_TO}"
puts "総デプロイ回数: #{merged_into_master_issues.items.size}回"
puts "平均デプロイ回数: #{((merged_into_master_issues.items.size).to_f / (business_days).to_f).round(3)}回/日"
puts "総変更数: #{pr_stats_list.size}"
puts "変更リードタイム（CIを除く）: #{(total_lead_time / pr_stats_list.size).round(3)}日"
puts "変更リードタイム（CI）: staging #{staging_ci_duration_seconds}秒 production #{master_ci_duration_seconds}秒"
puts "変更リードタイム: #{(total_lead_time / pr_stats_list.size + staging_ci_duration_days + master_ci_duration_days).round(3)}日"
