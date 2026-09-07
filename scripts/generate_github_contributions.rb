#!/usr/bin/env ruby

require "fileutils"
require "json"
require "net/http"
require "time"
require "uri"

GRAPHQL_ENDPOINT = URI("https://api.github.com/graphql")
SCHEMA_VERSION = 1

username = ENV.fetch("GH_USERNAME", "").strip
token = ENV.fetch("GITHUB_GRAPHQL_TOKEN", "").strip
output_path = ENV.fetch("OUTPUT_PATH", "public/github-contributions.json")

abort "GH_USERNAME is required." if username.empty?
abort "GITHUB_GRAPHQL_TOKEN is required." if token.empty?

to_time = Time.now.utc
from_time = to_time - (365 * 24 * 60 * 60)

query = <<~GRAPHQL
  query($login: String!, $from: DateTime!, $to: DateTime!) {
    user(login: $login) {
      login
      url
      contributionsCollection(from: $from, to: $to) {
        contributionCalendar {
          totalContributions
          colors
          months {
            name
            firstDay
            totalWeeks
            year
          }
          weeks {
            firstDay
            contributionDays {
              color
              contributionCount
              contributionLevel
              date
              weekday
            }
          }
        }
      }
    }
  }
GRAPHQL

request = Net::HTTP::Post.new(GRAPHQL_ENDPOINT)
request["Accept"] = "application/vnd.github+json"
request["Authorization"] = "Bearer #{token}"
request["Content-Type"] = "application/json"
request["User-Agent"] = "renamed-log-tistory-skin"
request.body = JSON.generate(
  query: query,
  variables: {
    login: username,
    from: from_time.iso8601,
    to: to_time.iso8601
  }
)

http = Net::HTTP.new(GRAPHQL_ENDPOINT.host, GRAPHQL_ENDPOINT.port)
http.use_ssl = true
http.open_timeout = 10
http.read_timeout = 30
response = http.request(request)

abort "GitHub GraphQL request failed with HTTP #{response.code}." unless response.is_a?(Net::HTTPSuccess)

body = JSON.parse(response.body)
if body["errors"]
  messages = body["errors"].map { |error| error["message"] }.compact.join(", ")
  abort "GitHub GraphQL returned an error: #{messages}"
end

user = body.dig("data", "user")
abort "GitHub user '#{username}' was not found." unless user

calendar = user.dig("contributionsCollection", "contributionCalendar")
abort "GitHub contribution calendar was not returned." unless calendar

payload = {
  schemaVersion: SCHEMA_VERSION,
  login: user["login"],
  profileUrl: user["url"],
  generatedAt: to_time.iso8601,
  from: from_time.iso8601,
  to: to_time.iso8601,
  totalContributions: calendar["totalContributions"],
  colors: calendar["colors"],
  months: calendar["months"],
  weeks: calendar["weeks"]
}

FileUtils.mkdir_p(File.dirname(output_path))
File.write(output_path, JSON.pretty_generate(payload) + "\n")
puts "Generated #{output_path} for #{user['login']}."
