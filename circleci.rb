require "circleci"
require "uri"
require "net/http"
require "openssl"

REPO = ENV["REPO"]

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
puts staging_insights.read_body
puts master_insights.read_body
