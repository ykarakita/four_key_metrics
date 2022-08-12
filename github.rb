require 'octokit'
require 'csv'

REPO = ENV["REPO"]
TIME_FORMAT = "%Y-%m-%d %H:%M:%S"

CREATED_FROM = "2022-01-01"
CREATED_TO = "2022-06-30"

PullRequestStats = Struct.new(:pr_number, :pr_title, :first_commit_datetime, :merged_into_staging_datetime, :merged_into_master_datetime, :pr_created_user_name, keyword_init: true)

def client
  Octokit::Client.new(access_token: ENV['ACCESS_TOKEN'], auto_paginate: true)
end

# @param datetime [Time]
# @return String
def format_datetime(datetime)
  datetime.localtime.strftime(TIME_FORMAT)
end

puts "期間内に master にマージされたデプロイ PR 一覧を取得します"

# 期間内に master にマージされたデプロイ PR 一覧を取得
query = "repo:#{REPO} state:closed base:master created:#{CREATED_FROM}..#{CREATED_TO}"
merged_into_master_issues = client.search_issues(query, per_page: 100)

pr_stats_list = []
merged_into_master_issues.items.each do |issue|
  printf "."
  merged_date = issue.pull_request.merged_at
  next unless merged_date

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
                                          merged_into_master_datetime: merged_date)
  end
end

puts
puts "計測対象の PR の情報を取得します"

pr_stats_list.each do |pr_stats|
  printf "."
  # 計測対象の PR の情報を取得
  pr = client.pull_request(REPO, pr_stats.pr_number)
  # 計測対象の PR に紐づく commits を取得
  commits = client.pull_request_commits(REPO, pr_stats.pr_number)

  # 計測対象の PR タイトル、最初のコミット日時、PR 作成者を格納
  pr_stats.pr_title = pr.title
  pr_stats.first_commit_datetime = commits.first.commit.committer.date
  pr_stats.pr_created_user_name = pr.user.login
  pr_stats
end

header = PullRequestStats.members.map(&:to_s)
generated_csv = CSV.generate(headers: header, write_headers: true, encoding: Encoding::UTF_8) do |csv|
  pr_stats_list.each do |pr_stats|
    csv << pr_stats.map { _1.is_a?(Time) ? format_datetime(_1) : _1 }
  end
end

begin
  File.open("artifacts/#{CREATED_FROM}_#{CREATED_TO}.csv", "w") do |file|
    file.write(generated_csv)
  end
rescue Errno::ENOENT
  Dir.mkdir("artifacts")
  retry
end

total_lead_time = pr_stats_list.inject(0) do |result , pr_stats|
  before_merge_into_staging_time = pr_stats.merged_into_staging_datetime - pr_stats.first_commit_datetime
  after_merged_into_staging_time = pr_stats.merged_into_master_datetime - pr_stats.merged_into_staging_datetime
  result += before_merge_into_staging_time + after_merged_into_staging_time
  result
end

puts
puts "#{CREATED_FROM} 〜 #{CREATED_TO} の capability"
puts "デプロイ回数: #{merged_into_master_issues.items.size}回"
puts "変更リードタイム（CI時間を除く）: #{((total_lead_time / 60 / 60 / 24) / pr_stats_list.size).round(3)}日"
