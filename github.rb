require 'octokit'
require 'csv'

REPO = ENV["REPO"]
TIME_FORMAT = "%Y-%m-%d %H:%M:%S"

CREATED_FROM = "2022-01-01"
# CREATED_TO = "2022-06-30"
CREATED_TO = "2022-01-05"

PullRequestStats = Struct.new(:pr_number, :pr_title, :first_commit_datetime, :merged_into_staging_datetime, :merged_into_master_datetime, :first_commit_user_name, :lead_time, keyword_init: true)

def client
  Octokit::Client.new(access_token: ENV['ACCESS_TOKEN'], auto_paginate: true)
end

# @param datetime [Time]
# @return String
def format_datetime(datetime)
  datetime.localtime.strftime(TIME_FORMAT)
end

if File.exists?("artifacts/#{CREATED_FROM}_#{CREATED_TO}_pr_stats_list.txt")
  dumped__merged_into_master_issues_data = File.read("artifacts/#{CREATED_FROM}_#{CREATED_TO}_merged_into_master_issues.txt")
  merged_into_master_issues = Marshal.restore(dumped__merged_into_master_issues_data)
  dumped_pr_stats_list_data = File.read("artifacts/#{CREATED_FROM}_#{CREATED_TO}_pr_stats_list.txt")
  pr_stats_list = Marshal.restore(dumped_pr_stats_list_data)
else
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
    pr_stats.lead_time = lead_time_sec / 60 / 60 / 24
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

    File.open("artifacts/#{CREATED_FROM}_#{CREATED_TO}_pr_stats_list.txt", "w") do |file|
      file.write(Marshal.dump(pr_stats_list))
    end

    File.open("artifacts/#{CREATED_FROM}_#{CREATED_TO}_merged_into_master_issues.txt", "w") do |file|
      file.write(Marshal.dump(merged_into_master_issues))
    end
  rescue Errno::ENOENT
    Dir.mkdir("artifacts")
    retry
  end
end

total_lead_time = pr_stats_list.map(&:lead_time).sum

# ここでは大まかな営業日の割合を計算に使います
# 1年の中で休日が120日、平日が245日。そこから 245 / 365 = 0.67 としています
business_days = ((Time.parse(CREATED_TO) - Time.parse(CREATED_FROM)) / 60 / 60 / 24 * 0.67).to_i

puts
puts "#{CREATED_FROM} 〜 #{CREATED_TO} の capability"
puts "デプロイ回数: #{merged_into_master_issues.items.size}回"
puts "平均デプロイ回数: #{business_days / merged_into_master_issues.items.size}回/日"
puts "デプロイ頻度: #{merged_into_master_issues.items.size}回"
puts "変更リードタイム（CI時間を除く）: #{(total_lead_time / pr_stats_list.size).round(3)}日"
