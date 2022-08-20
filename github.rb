require 'octokit'

class Github
  PullRequestStats = Struct.new(:pr_number, :pr_title, :first_commit_datetime, :merged_into_staging_datetime, :merged_into_master_datetime, :first_commit_user_name, :lead_time, keyword_init: true)

  attr_reader :merged_into_master_issues, :pr_stats_list

  def initialize(access_token:, repo:)
    @access_token = access_token
    @repo = repo
    @pr_stats_list = []
  end

  # @return Integer
  def get_total_lead_time(from:, to:)
    get_merged_into_master_issues(from:, to:)

    merged_into_master_issues.items.each do |issue|
      printf "."
      merged_date = issue.pull_request.merged_at

      # デプロイ PR のコミット一覧から、計測対象の PR の number、 staging マージ日時を取得
      pull_request_number = issue.number
      commits = client.pull_request_commits(repo, pull_request_number)

      commits.each do |commit|
        commit_message = commit.commit.message
        next if commit_message.include?("dependabot") || commit_message.include?("renovate")

        pull_request_number = commit_message.slice(/Merge pull request #\d+/)&.slice(/\d+/)
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

      # 計測対象の PR タイトル、最初のコミット日時、PR 作成者を格納
      first_commit = commits.first.commit
      pr_stats.first_commit_datetime = first_commit.committer.date
      pr_stats.first_commit_user_name = first_commit.author.name

      # 各 PR のリードタイムを計測
      before_merge_into_staging_time = pr_stats.merged_into_staging_datetime - pr_stats.first_commit_datetime
      after_merged_into_staging_time = pr_stats.merged_into_master_datetime - pr_stats.merged_into_staging_datetime
      lead_time_sec = before_merge_into_staging_time + after_merged_into_staging_time
      pr_stats.lead_time = lead_time_sec
    end

    pr_stats_list.filter { !_1.first_commit_user_name.include?("dependabot") || !_1.first_commit_user_name.include?("renovate") }
                 .map(&:lead_time).sum
  end

  private

  attr_reader :repo

  def client
    @client ||= Octokit::Client.new(access_token: @access_token, auto_paginate: true)
  end

  def get_merged_into_master_issues(from:, to:)
    puts "#{from} 〜 #{to} に master にマージされたデプロイ PR 一覧を取得します"
    query = "repo:#{repo} is:merged base:master merged:#{from}..#{to}"
    @merged_into_master_issues = client.search_issues(query, per_page: 100)
  end
end
