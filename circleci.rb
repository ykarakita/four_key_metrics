require "circleci"
require "uri"
require "net/http"
require "openssl"

class Circleci
  def initialize(access_token:, repo:)
    @access_token = access_token
    @repo = repo
  end

  def get_duration_metrics_median(branch:)
    endpoint = "https://circleci.com/api/v2/insights/gh/#{repo}/workflows?branch=#{branch}&reporting-window=last-90-days"
    response = request_circleci(endpoint)
    parsed_response = JSON.parse(response.read_body)

    return 0 unless parsed_response["items"].size

    parsed_response["items"][0]["metrics"]["duration_metrics"]["median"]
  end

  private

  attr_reader :repo

  def request_circleci(endpoint)
    url = URI(endpoint)
    headers = { "Circle-Token" => @access_token }

    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    request = Net::HTTP::Get.new(url, headers)
    http.request(request)
  end
end
