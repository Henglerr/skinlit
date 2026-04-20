#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "json"
require "net/http"
require "openssl"
require "optparse"
require "time"
require "uri"

class AppStoreConnectError < StandardError; end

class EnvFileLoader
  def self.load(path, env)
    absolute_path = File.expand_path(path)
    base_dir = File.dirname(absolute_path)

    File.readlines(absolute_path, chomp: true).each do |line|
      stripped = line.strip
      next if stripped.empty? || stripped.start_with?("#")

      stripped = stripped.sub(/\Aexport\s+/, "")
      key, raw_value = stripped.split("=", 2)
      raise AppStoreConnectError, "Invalid env line in #{absolute_path}: #{line}" if key.nil? || raw_value.nil?

      value = unquote(raw_value.strip)
      if key == "ASC_PRIVATE_KEY_PATH" && !value.empty? && !value.start_with?("/")
        value = File.expand_path(value, base_dir)
      end

      env[key] = value
    end
  end

  def self.unquote(value)
    if (value.start_with?('"') && value.end_with?('"')) || (value.start_with?("'") && value.end_with?("'"))
      value[1...-1]
    else
      value
    end
  end
end

class AppStoreConnectClient
  BASE_URL = "https://api.appstoreconnect.apple.com"
  TOKEN_LIFETIME_SECONDS = 20 * 60

  def initialize(env)
    @env = env
  end

  def list_apps(bundle_id: nil, limit: 50)
    query = {
      "fields[apps]" => "name,bundleId,sku,subscriptionStatusUrl,subscriptionStatusUrlForSandbox"
    }
    query["filter[bundleId]"] = bundle_id if bundle_id
    query["limit"] = limit.to_s
    get_collection("/v1/apps", query)
  end

  def find_app!(bundle_id)
    apps = list_apps(bundle_id: bundle_id, limit: 2)
    app = apps.fetch("data", []).first
    raise AppStoreConnectError, "No App Store Connect app found for bundle ID #{bundle_id}" unless app

    app
  end

  def subscription_groups_for_app(app_id)
    response = get_json(
      "/v1/apps/#{app_id}",
      {
        "include" => "subscriptionGroups",
        "fields[apps]" => "name,bundleId,sku,subscriptionStatusUrl,subscriptionStatusUrlForSandbox,subscriptionGroups",
        "fields[subscriptionGroups]" => "referenceName"
      }
    )

    response.fetch("included", []).select { |item| item["type"] == "subscriptionGroups" }
  end

  def subscription_group_details(group_id)
    response = get_json(
      "/v1/subscriptionGroups/#{group_id}",
      {
        "include" => "subscriptions,subscriptionGroupLocalizations",
        "fields[subscriptionGroups]" => "referenceName,subscriptions,subscriptionGroupLocalizations",
        "fields[subscriptionGroupLocalizations]" => "name,locale,state",
        "fields[subscriptions]" => "name,productId,familySharable,state,subscriptionPeriod,groupLevel"
      }
    )

    data = response.fetch("data")
    included = response.fetch("included", [])
    group_localizations = included.select { |item| item["type"] == "subscriptionGroupLocalizations" }
    subscriptions = included.select { |item| item["type"] == "subscriptions" }

    {
      "data" => data,
      "groupLocalizations" => group_localizations,
      "subscriptions" => subscriptions
    }
  end

  def subscription_details(subscription_id)
    response = get_json(
      "/v1/subscriptions/#{subscription_id}",
      {
        "include" => "subscriptionLocalizations",
        "fields[subscriptions]" => "name,productId,familySharable,state,subscriptionPeriod,groupLevel,subscriptionLocalizations",
        "fields[subscriptionLocalizations]" => "name,locale,description,state"
      }
    )

    {
      "data" => response.fetch("data"),
      "localizations" => response.fetch("included", []).select { |item| item["type"] == "subscriptionLocalizations" }
    }
  end

  def raw(path, params = {})
    get_json(path, params)
  end

  private

  attr_reader :env

  def get_collection(path, params = {})
    response = get_json(path, params)
    data = Array(response["data"])
    included = Array(response["included"])

    next_link = response.dig("links", "next")
    while next_link
      page = get_json(next_link)
      data.concat(Array(page["data"]))
      included.concat(Array(page["included"]))
      next_link = page.dig("links", "next")
    end

    {
      "data" => data,
      "included" => included,
      "links" => response["links"],
      "meta" => response["meta"]
    }
  end

  def get_json(path_or_url, params = {})
    uri = build_uri(path_or_url, params)
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{jwt_token}"
    request["Content-Type"] = "application/json"
    request["Accept"] = "application/json"

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
      http.request(request)
    end

    body = response.body.to_s
    parsed = body.empty? ? {} : JSON.parse(body)

    return parsed if response.is_a?(Net::HTTPSuccess)

    error_details = Array(parsed["errors"]).map do |error|
      detail = error["detail"]
      title = error["title"]
      [title, detail].compact.join(": ")
    end

    message = if error_details.empty?
      "HTTP #{response.code} from App Store Connect"
    else
      "HTTP #{response.code} from App Store Connect: #{error_details.join(" | ")}"
    end

    raise AppStoreConnectError, message
  end

  def build_uri(path_or_url, params)
    uri =
      if path_or_url.start_with?("http://", "https://")
        URI(path_or_url)
      else
        URI.join(BASE_URL, path_or_url)
      end

    unless params.empty?
      existing_pairs = uri.query ? URI.decode_www_form(uri.query) : []
      merged_pairs = existing_pairs + params.to_a
      uri.query = URI.encode_www_form(merged_pairs)
    end

    uri
  end

  def jwt_token
    issuer_id = fetch_required_env("ASC_ISSUER_ID")
    key_id = fetch_required_env("ASC_KEY_ID")
    private_key = OpenSSL::PKey.read(private_key_pem)
    now = Time.now.to_i

    header = { alg: "ES256", kid: key_id, typ: "JWT" }
    payload = {
      iss: issuer_id,
      iat: now,
      exp: now + TOKEN_LIFETIME_SECONDS,
      aud: "appstoreconnect-v1"
    }

    encoded_header = base64url_encode(JSON.generate(header))
    encoded_payload = base64url_encode(JSON.generate(payload))
    signing_input = "#{encoded_header}.#{encoded_payload}"
    digest = OpenSSL::Digest::SHA256.digest(signing_input)
    der_signature = private_key.dsa_sign_asn1(digest)
    jose_signature = der_signature_to_jose(der_signature)

    "#{signing_input}.#{base64url_encode(jose_signature)}"
  end

  def private_key_pem
    inline_key = env["ASC_PRIVATE_KEY"].to_s.strip
    return inline_key unless inline_key.empty?

    key_path = fetch_required_env("ASC_PRIVATE_KEY_PATH")
    raise AppStoreConnectError, "Private key file not found at #{key_path}" unless File.exist?(key_path)

    File.read(key_path)
  end

  def fetch_required_env(key)
    value = env[key].to_s.strip
    raise AppStoreConnectError, "Missing #{key}. See docs/app-store-connect-cli.md for setup." if value.empty?

    value
  end

  def base64url_encode(value)
    Base64.urlsafe_encode64(value, padding: false)
  end

  def der_signature_to_jose(der_signature)
    sequence = OpenSSL::ASN1.decode(der_signature)
    raise AppStoreConnectError, "Unexpected ECDSA signature format" unless sequence.is_a?(OpenSSL::ASN1::Sequence)

    r = integer_to_fixed_width_bytes(sequence.value[0].value, 32)
    s = integer_to_fixed_width_bytes(sequence.value[1].value, 32)
    r + s
  end

  def integer_to_fixed_width_bytes(integer_value, width)
    hex = integer_value.to_s(16)
    hex = "0#{hex}" if hex.length.odd?
    bytes = [hex].pack("H*")
    bytes = bytes.byteslice(-width, width) if bytes.bytesize > width
    bytes.rjust(width, "\x00")
  end
end

class AppStoreConnectCLI
  DEFAULT_ENV_FILE = File.expand_path("../Config/Environment/app_store_connect.env", __dir__)

  def initialize(argv, stdout: $stdout, stderr: $stderr, env: ENV.to_h)
    @argv = argv.dup
    @stdout = stdout
    @stderr = stderr
    @env = env
    @default_env_loaded = false
    load_env_file_if_present
  end

  def run
    command = argv.shift

    case command
    when nil, "help", "--help", "-h"
      stdout.puts(help_text)
      0
    when "apps"
      run_apps(argv)
    when "subscriptions"
      run_subscriptions(argv)
    when "doctor"
      run_doctor(argv)
    when "raw"
      run_raw(argv)
    else
      raise AppStoreConnectError, "Unknown command #{command.inspect}. Run `ruby scripts/app_store_connect_cli.rb help`."
    end
  rescue OptionParser::ParseError => error
    stderr.puts("error: #{error.message}")
    stderr.puts
    stderr.puts(help_text)
    1
  rescue AppStoreConnectError => error
    stderr.puts("error: #{error.message}")
    1
  end

  private

  attr_reader :argv, :stdout, :stderr, :env

  def client
    @client ||= AppStoreConnectClient.new(env)
  end

  def run_apps(arguments)
    options = { bundle_id: nil, json: false }

    OptionParser.new do |parser|
      parser.banner = "Usage: ruby scripts/app_store_connect_cli.rb apps [--bundle-id BUNDLE] [--json]"
      parser.on("--bundle-id BUNDLE", "Filter to a single bundle ID") { |value| options[:bundle_id] = value }
      parser.on("--json", "Print raw JSON") { options[:json] = true }
    end.parse!(arguments)

    result = client.list_apps(bundle_id: options[:bundle_id])
    return print_json(result) if options[:json]

    apps = result.fetch("data", [])
    if apps.empty?
      stdout.puts("No apps found.")
      return 0
    end

    apps.each do |app|
      attrs = app.fetch("attributes", {})
      stdout.puts("#{attrs["name"]} (#{app["id"]})")
      stdout.puts("  Bundle ID: #{attrs["bundleId"]}")
      stdout.puts("  SKU: #{attrs["sku"]}") unless attrs["sku"].to_s.empty?
      sandbox_status_url = attrs["subscriptionStatusUrlForSandbox"]
      stdout.puts("  Sandbox status URL: #{sandbox_status_url}") unless sandbox_status_url.to_s.empty?
      stdout.puts
    end

    0
  end

  def run_subscriptions(arguments)
    options = { bundle_id: nil, json: false }

    OptionParser.new do |parser|
      parser.banner = "Usage: ruby scripts/app_store_connect_cli.rb subscriptions --bundle-id BUNDLE [--json]"
      parser.on("--bundle-id BUNDLE", "Bundle ID to inspect") { |value| options[:bundle_id] = value }
      parser.on("--json", "Print raw JSON") { options[:json] = true }
    end.parse!(arguments)

    raise AppStoreConnectError, "--bundle-id is required" if options[:bundle_id].to_s.empty?

    report = build_subscription_report(options[:bundle_id])
    return print_json(report) if options[:json]

    print_subscription_report(report, include_issues: false)
    0
  end

  def run_doctor(arguments)
    options = { bundle_id: nil, json: false }

    OptionParser.new do |parser|
      parser.banner = "Usage: ruby scripts/app_store_connect_cli.rb doctor --bundle-id BUNDLE [--json]"
      parser.on("--bundle-id BUNDLE", "Bundle ID to inspect") { |value| options[:bundle_id] = value }
      parser.on("--json", "Print raw JSON") { options[:json] = true }
    end.parse!(arguments)

    raise AppStoreConnectError, "--bundle-id is required" if options[:bundle_id].to_s.empty?

    report = build_subscription_report(options[:bundle_id])
    report["issues"] = derive_issues(report)
    return print_json(report) if options[:json]

    print_subscription_report(report, include_issues: true)
    0
  end

  def run_raw(arguments)
    options = { params: {} }

    OptionParser.new do |parser|
      parser.banner = "Usage: ruby scripts/app_store_connect_cli.rb raw PATH [--param KEY=VALUE]"
      parser.on("--param KEY=VALUE", "Repeatable query string params") do |value|
        key, param_value = value.split("=", 2)
        raise OptionParser::ParseError, "Expected KEY=VALUE for --param" if key.nil? || param_value.nil?

        options[:params][key] = param_value
      end
    end.parse!(arguments)

    path = arguments.shift
    raise AppStoreConnectError, "PATH is required for raw" if path.to_s.empty?

    print_json(client.raw(path, options[:params]))
    0
  end

  def build_subscription_report(bundle_id)
    app = client.find_app!(bundle_id)
    app_attrs = app.fetch("attributes", {})
    group_summaries = client.subscription_groups_for_app(app["id"]).map do |group|
      details = client.subscription_group_details(group["id"])
      subscriptions = details.fetch("subscriptions").map do |subscription|
        subscription_details = client.subscription_details(subscription["id"])
        build_subscription_summary(subscription_details)
      end.sort_by { |subscription| [subscription["groupLevel"] || 0, subscription["productId"].to_s] }

      {
        "id" => group["id"],
        "referenceName" => details.dig("data", "attributes", "referenceName"),
        "localizations" => details.fetch("groupLocalizations").map { |localization| localization_summary(localization) }.sort_by { |item| item["locale"].to_s },
        "subscriptions" => subscriptions
      }
    end.sort_by { |group| group["referenceName"].to_s }

    {
      "app" => {
        "id" => app["id"],
        "name" => app_attrs["name"],
        "bundleId" => app_attrs["bundleId"],
        "sku" => app_attrs["sku"],
        "subscriptionStatusUrl" => app_attrs["subscriptionStatusUrl"],
        "subscriptionStatusUrlForSandbox" => app_attrs["subscriptionStatusUrlForSandbox"]
      },
      "subscriptionGroups" => group_summaries
    }
  end

  def build_subscription_summary(details)
    data = details.fetch("data")
    attributes = data.fetch("attributes", {})

    {
      "id" => data["id"],
      "name" => attributes["name"],
      "productId" => attributes["productId"],
      "state" => attributes["state"],
      "groupLevel" => attributes["groupLevel"],
      "familySharable" => attributes["familySharable"],
      "subscriptionPeriod" => attributes["subscriptionPeriod"],
      "localizations" => details.fetch("localizations").map { |localization| localization_summary(localization) }.sort_by { |item| item["locale"].to_s }
    }
  end

  def localization_summary(resource)
    attributes = resource.fetch("attributes", {})
    {
      "id" => resource["id"],
      "locale" => attributes["locale"],
      "name" => attributes["name"],
      "state" => attributes["state"]
    }
  end

  def derive_issues(report)
    issues = []
    groups = report.fetch("subscriptionGroups")

    issues << "No subscription groups found for this app." if groups.empty?

    groups.each do |group|
      if group.fetch("localizations").empty?
        issues << "Subscription group #{group["referenceName"] || group["id"]} has no localizations."
      end

      group.fetch("subscriptions").each do |subscription|
        state = subscription["state"].to_s
        if state.empty?
          issues << "Subscription #{subscription["productId"] || subscription["id"]} is missing a state."
        elsif state != "APPROVED"
          issues << "Subscription #{subscription["productId"]} is in state #{state}."
        end

        if subscription.fetch("localizations").empty?
          issues << "Subscription #{subscription["productId"]} has no subscription localizations."
        end
      end
    end

    issues
  end

  def print_subscription_report(report, include_issues:)
    app = report.fetch("app")
    stdout.puts("App: #{app["name"]} (#{app["id"]})")
    stdout.puts("Bundle ID: #{app["bundleId"]}")
    stdout.puts("SKU: #{app["sku"]}") unless app["sku"].to_s.empty?
    unless app["subscriptionStatusUrlForSandbox"].to_s.empty?
      stdout.puts("Sandbox Subscription Status URL: #{app["subscriptionStatusUrlForSandbox"]}")
    end
    unless app["subscriptionStatusUrl"].to_s.empty?
      stdout.puts("Production Subscription Status URL: #{app["subscriptionStatusUrl"]}")
    end
    stdout.puts

    groups = report.fetch("subscriptionGroups")
    if groups.empty?
      stdout.puts("No subscription groups found.")
    else
      groups.each do |group|
        stdout.puts("Group: #{group["referenceName"] || group["id"]}")
        if group.fetch("localizations").empty?
          stdout.puts("  Group localizations: none")
        else
          localization_text = group.fetch("localizations").map do |localization|
            "#{localization["locale"]}: #{localization["name"]} [#{localization["state"]}]"
          end.join(" | ")
          stdout.puts("  Group localizations: #{localization_text}")
        end

        if group.fetch("subscriptions").empty?
          stdout.puts("  Subscriptions: none")
          stdout.puts
          next
        end

        group.fetch("subscriptions").each do |subscription|
          stdout.puts("  Product: #{subscription["productId"]}")
          stdout.puts("    Name: #{subscription["name"]}") unless subscription["name"].to_s.empty?
          stdout.puts("    State: #{subscription["state"]}")
          stdout.puts("    Group level: #{subscription["groupLevel"]}") unless subscription["groupLevel"].nil?
          stdout.puts("    Period: #{subscription["subscriptionPeriod"]}") unless subscription["subscriptionPeriod"].to_s.empty?
          stdout.puts("    Family sharable: #{subscription["familySharable"]}")

          if subscription.fetch("localizations").empty?
            stdout.puts("    Localizations: none")
          else
            localization_text = subscription.fetch("localizations").map do |localization|
              "#{localization["locale"]}: #{localization["name"]} [#{localization["state"]}]"
            end.join(" | ")
            stdout.puts("    Localizations: #{localization_text}")
          end
        end

        stdout.puts
      end
    end

    return unless include_issues

    issues = report.fetch("issues")
    if issues.empty?
      stdout.puts("Doctor checks: no obvious API-visible blockers found.")
    else
      stdout.puts("Potential blockers:")
      issues.each { |issue| stdout.puts("  - #{issue}") }
    end
  end

  def print_json(value)
    stdout.puts(JSON.pretty_generate(value))
    0
  end

  def load_env_file_if_present
    explicit_env_file = extract_flag_value!("--env-file")
    if explicit_env_file
      raise AppStoreConnectError, "Env file not found at #{explicit_env_file}" unless File.exist?(explicit_env_file)

      EnvFileLoader.load(explicit_env_file, env)
      return
    end

    env_file_path = default_env_file_path
    return unless env_file_path

    EnvFileLoader.load(env_file_path, env)
  end

  def default_env_file_path
    candidate = File.expand_path(DEFAULT_ENV_FILE, Dir.pwd)
    File.exist?(candidate) ? candidate : nil
  end

  def extract_flag_value!(flag_name)
    index = argv.index(flag_name)
    if index
      value = argv[index + 1]
      raise AppStoreConnectError, "#{flag_name} requires a value" if value.nil?

      argv.slice!(index, 2)
      return value
    end

    combined = argv.find { |argument| argument.start_with?("#{flag_name}=") }
    return nil unless combined

    argv.delete(combined)
    combined.split("=", 2).last
  end

  def help_text
    <<~TEXT
      App Store Connect CLI

      Usage:
        ruby scripts/app_store_connect_cli.rb [--env-file PATH] COMMAND [options]

      Commands:
        apps                         List apps visible to the API key
        subscriptions                List subscription groups and subscriptions for an app
        doctor                       Run a subscription-focused health check for an app
        raw                          Fetch any App Store Connect API path as JSON
        help                         Show this help text

      Common examples:
        ruby scripts/app_store_connect_cli.rb apps
        ruby scripts/app_store_connect_cli.rb apps --bundle-id com.skinlit.SkinLit
        ruby scripts/app_store_connect_cli.rb subscriptions --bundle-id com.skinlit.SkinLit
        ruby scripts/app_store_connect_cli.rb doctor --bundle-id com.skinlit.SkinLit
        ruby scripts/app_store_connect_cli.rb raw /v1/apps

      Credentials:
        The script reads these values from the environment or from Config/Environment/app_store_connect.env:
          ASC_ISSUER_ID
          ASC_KEY_ID
          ASC_PRIVATE_KEY_PATH

      Notes:
        - The default local env file is #{DEFAULT_ENV_FILE}
        - Use --env-file PATH to point at a different local credential file
        - Keep .p8 keys out of git
    TEXT
  end
end

begin
  exit(AppStoreConnectCLI.new(ARGV).run)
rescue AppStoreConnectError => error
  warn("error: #{error.message}")
  exit(1)
end
