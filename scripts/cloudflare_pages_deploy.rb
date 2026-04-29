#!/usr/bin/env ruby

require "base64"
require "digest"
require "json"
require "net/http"
require "pathname"
require "securerandom"
require "set"
require "uri"

API_BASE = "https://api.cloudflare.com/client/v4"
PROJECT_NAME = ENV.fetch("CLOUDFLARE_PROJECT_NAME", "the-gap-has-weight")
DEPLOY_DIR = File.expand_path(ENV.fetch("CLOUDFLARE_DEPLOY_DIR", "public"), Dir.pwd)
PRODUCTION_BRANCH = "main"

def api_token
  ENV["CLOUDFLARE_API_TOKEN"] || abort("Missing CLOUDFLARE_API_TOKEN")
end

def api_request(method, path, body: nil, headers: {}, expected_status: nil)
  uri = URI("#{API_BASE}#{path}")
  request_class = Net::HTTP.const_get(method.capitalize)
  request = request_class.new(uri)
  request["Authorization"] = "Bearer #{api_token}"
  headers.each { |key, value| request[key] = value }
  request.body = body if body

  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(request)
  end

  if expected_status && response.code.to_i != expected_status
    abort("Unexpected HTTP #{response.code} for #{path}: #{response.body}")
  end

  parsed = JSON.parse(response.body)
  abort("Cloudflare API error for #{path}: #{response.body}") unless parsed["success"]
  parsed["result"]
rescue JSON::ParserError
  abort("Failed to parse Cloudflare response for #{path}: #{response.body}")
end

def project_exists?(account_id)
  uri = URI("#{API_BASE}/accounts/#{account_id}/pages/projects/#{PROJECT_NAME}")
  request = Net::HTTP::Get.new(uri)
  request["Authorization"] = "Bearer #{api_token}"

  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(request)
  end

  return true if response.code.to_i == 200
  return false if response.code.to_i == 404

  parsed = JSON.parse(response.body)
  abort("Cloudflare API error for /accounts/#{account_id}/pages/projects/#{PROJECT_NAME}: #{response.body}") unless parsed["success"]
  true
rescue JSON::ParserError
  abort("Failed to parse Cloudflare response for /accounts/#{account_id}/pages/projects/#{PROJECT_NAME}: #{response.body}")
end

def infer_account_id
  configured = ENV["CLOUDFLARE_ACCOUNT_ID"]
  return configured unless configured.nil? || configured.empty?

  memberships = api_request("get", "/memberships")
  accounts = memberships.filter_map { |membership| membership["account"] }
  unique_accounts = accounts.uniq { |account| account["id"] }

  if unique_accounts.size == 1
    unique_accounts.first["id"]
  else
    names = unique_accounts.map { |account| "#{account['name']} (#{account['id']})" }.join(", ")
    abort("Multiple Cloudflare accounts available. Set CLOUDFLARE_ACCOUNT_ID explicitly. Accounts: #{names}")
  end
end

def ensure_project(account_id)
  return if project_exists?(account_id)

  payload = {
    name: PROJECT_NAME,
    production_branch: PRODUCTION_BRANCH,
    build_config: {
      build_command: "",
      destination_dir: "public",
      root_dir: "/"
    }
  }
  api_request(
    "post",
    "/accounts/#{account_id}/pages/projects",
    body: JSON.generate(payload),
    headers: { "Content-Type" => "application/json" },
    expected_status: 200
  )
end

def upload_token(account_id)
  api_request("get", "/accounts/#{account_id}/pages/projects/#{PROJECT_NAME}/upload-token")["jwt"]
end

def upload_request(method, path, jwt:, body:, content_type: "application/json")
  uri = URI("#{API_BASE}#{path}")
  request_class = Net::HTTP.const_get(method.capitalize)
  request = request_class.new(uri)
  request["Authorization"] = "Bearer #{jwt}"
  request["Content-Type"] = content_type
  request.body = body

  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(request)
  end

  parsed = JSON.parse(response.body)
  abort("Cloudflare upload error for #{path}: #{response.body}") unless parsed["success"]
  parsed["result"]
end

def content_type_for(path)
  case File.extname(path)
  when ".html" then "text/html"
  when ".css" then "text/css"
  when ".js" then "application/javascript"
  when ".json" then "application/json"
  when ".svg" then "image/svg+xml"
  when ".png" then "image/png"
  when ".jpg", ".jpeg" then "image/jpeg"
  when ".webp" then "image/webp"
  when ".gif" then "image/gif"
  when ".txt", "" then "text/plain"
  else "application/octet-stream"
  end
end

def ignored?(relative_path)
  parts = relative_path.split(File::SEPARATOR)
  return true if parts.include?("functions")
  return true if parts.include?("node_modules")
  return true if parts.include?(".git")
  return true if parts.include?(".wrangler")

  ["_worker.js", "_redirects", "_headers", "_routes.json", ".DS_Store"].include?(relative_path) ||
    relative_path.end_with?("/.DS_Store")
end

def file_hash(contents, path)
  ext = File.extname(path).delete_prefix(".")
  Digest::MD5.hexdigest("#{Base64.strict_encode64(contents)}#{ext}")
end

def collect_assets(directory)
  root = Pathname.new(directory)
  files = {}

  Dir.glob(File.join(directory, "**", "*"), File::FNM_DOTMATCH).sort.each do |absolute_path|
    next unless File.file?(absolute_path)

    relative_path = Pathname.new(absolute_path).relative_path_from(root).to_s
    next if ignored?(relative_path)

    contents = File.binread(absolute_path)
    hash = file_hash(contents, relative_path)
    files[relative_path] = {
      absolute_path: absolute_path,
      contents: contents,
      hash: hash,
      content_type: content_type_for(relative_path)
    }
  end

  files
end

def upload_assets(jwt, files)
  hashes = files.values.map { |file| file[:hash] }
  missing_hashes = upload_request("post", "/pages/assets/check-missing", jwt: jwt, body: JSON.generate({ hashes: hashes }))
  missing_set = missing_hashes.to_set

  payload = files.values.select { |file| missing_set.include?(file[:hash]) }.map do |file|
    {
      key: file[:hash],
      value: Base64.strict_encode64(file[:contents]),
      metadata: {
        contentType: file[:content_type]
      },
      base64: true
    }
  end

  unless payload.empty?
    upload_request("post", "/pages/assets/upload", jwt: jwt, body: JSON.generate(payload))
  end

  upload_request("post", "/pages/assets/upsert-hashes", jwt: jwt, body: JSON.generate({ hashes: hashes }))
end

def multipart_body(fields)
  boundary = "----copilot-pages-#{SecureRandom.hex(12)}"
  chunks = []

  fields.each do |field|
    chunks << "--#{boundary}\r\n"
    if field[:filename]
      chunks << "Content-Disposition: form-data; name=\"#{field[:name]}\"; filename=\"#{field[:filename]}\"\r\n"
      chunks << "Content-Type: #{field[:content_type] || 'application/octet-stream'}\r\n\r\n"
      chunks << field[:value]
      chunks << "\r\n"
    else
      chunks << "Content-Disposition: form-data; name=\"#{field[:name]}\"\r\n\r\n"
      chunks << field[:value]
      chunks << "\r\n"
    end
  end

  chunks << "--#{boundary}--\r\n"
  [boundary, chunks.join]
end

def deployment_fields(manifest)
  fields = [
    { name: "manifest", value: JSON.generate(manifest) },
    { name: "branch", value: PRODUCTION_BRANCH },
    { name: "commit_dirty", value: "true" },
    { name: "commit_message", value: "Deploy The Gap Has Weight" },
    { name: "pages_build_output_dir", value: "public" }
  ]

  headers_path = File.join(DEPLOY_DIR, "_headers")
  if File.exist?(headers_path)
    fields << {
      name: "_headers",
      filename: "_headers",
      content_type: "text/plain",
      value: File.binread(headers_path)
    }
  end

  redirects_path = File.join(DEPLOY_DIR, "_redirects")
  if File.exist?(redirects_path)
    fields << {
      name: "_redirects",
      filename: "_redirects",
      content_type: "text/plain",
      value: File.binread(redirects_path)
    }
  end

  fields
end

def create_deployment(account_id, manifest)
  boundary, body = multipart_body(deployment_fields(manifest))
  api_request(
    "post",
    "/accounts/#{account_id}/pages/projects/#{PROJECT_NAME}/deployments",
    body: body,
    headers: { "Content-Type" => "multipart/form-data; boundary=#{boundary}" },
    expected_status: 200
  )
end

def wait_for_deployment(account_id, deployment_id)
  30.times do
    deployment = api_request("get", "/accounts/#{account_id}/pages/projects/#{PROJECT_NAME}/deployments/#{deployment_id}")
    latest_stage = deployment["latest_stage"] || {}
    status = latest_stage["status"]

    return deployment if status == "success"
    abort("Deployment failed: #{deployment.to_json}") if ["failure", "canceled"].include?(status)

    sleep 2
  end

  abort("Timed out waiting for deployment to complete")
end

abort("Deploy directory not found: #{DEPLOY_DIR}") unless Dir.exist?(DEPLOY_DIR)

account_id = infer_account_id
ensure_project(account_id)
jwt = upload_token(account_id)
files = collect_assets(DEPLOY_DIR)
abort("No deployable files found in #{DEPLOY_DIR}") if files.empty?

upload_assets(jwt, files)
manifest = files.each_with_object({}) do |(relative_path, file), result|
  result["/#{relative_path.tr(File::SEPARATOR, "/")}"] = file[:hash]
end

deployment = create_deployment(account_id, manifest)
final_deployment = wait_for_deployment(account_id, deployment["id"])

puts JSON.pretty_generate(
  {
    project: PROJECT_NAME,
    account_id: account_id,
    deployment_id: final_deployment["id"],
    url: final_deployment["url"],
    stage: final_deployment.dig("latest_stage", "status")
  }
)