# frozen_string_literal: true

require "jwt"
require "faraday"
require "openssl"
require "json"
require "base64"

module ASC
  # Minimal App Store Connect API v1 client. Reuses the exact same
  # ASC_KEY_ID / ASC_ISSUER_ID / ASC_PRIVATE_KEY env vars fastlane's own
  # `app_store_connect_api_key` action already consumes (see Fastfile's
  # `use_api_key` lane) — ASC_PRIVATE_KEY is base64 of the .p8 file content.
  #
  # Exists because fastlane's `deliver`/`upload_to_app_store` has no support
  # for Custom Product Pages (confirmed: open feature request, not
  # implemented) even though the App Store Connect API itself does.
  class Client
    BASE_URL = "https://api.appstoreconnect.apple.com/v1"

    def initialize(
      key_id: ENV["ASC_KEY_ID"],
      issuer_id: ENV["ASC_ISSUER_ID"],
      private_key_base64: ENV["ASC_PRIVATE_KEY"]
    )
      unless key_id && issuer_id && private_key_base64
        raise "ASC_KEY_ID / ASC_ISSUER_ID / ASC_PRIVATE_KEY must all be set " \
              "(same env vars fastlane's app_store_connect_api_key action uses)"
      end
      @key_id = key_id
      @issuer_id = issuer_id
      @private_key = OpenSSL::PKey::EC.new(Base64.decode64(private_key_base64))
      @conn = Faraday.new(url: BASE_URL)
    end

    def get(path, params = {})
      parse(@conn.get(path, params) { |req| apply_auth(req) })
    end

    def post(path, body)
      parse(@conn.post(path) { |req| apply_auth(req, body) })
    end

    def patch(path, body)
      parse(@conn.patch(path) { |req| apply_auth(req, body) })
    end

    # Screenshot/app-preview bytes go to a pre-signed URL ASC hands back from
    # a POST /appScreenshots reservation — authenticated by the headers ASC
    # provides in `uploadOperations`, not our JWT.
    def put_raw(url, headers, data)
      response = Faraday.new.put(url) do |req|
        headers.each { |h| req.headers[h["name"]] = h["value"] }
        req.body = data
      end
      unless (200..299).cover?(response.status)
        raise "Upload PUT to #{url} failed: #{response.status}\n#{response.body}"
      end
      response
    end

    private

    def apply_auth(req, body = nil)
      req.headers["Authorization"] = "Bearer #{token}"
      if body
        req.headers["Content-Type"] = "application/json"
        req.body = JSON.generate(body)
      end
    end

    def parse(response)
      parsed =
        begin
          response.body.nil? || response.body.empty? ? nil : JSON.parse(response.body)
        rescue JSON::ParserError
          nil
        end

      unless (200..299).cover?(response.status)
        detail = parsed ? (parsed["errors"] || parsed) : response.body
        raise "ASC API error #{response.status}: #{detail}"
      end

      parsed
    end

    def token
      now = Time.now.to_i
      payload = {
        iss: @issuer_id,
        iat: now,
        # ASC caps JWT lifetime at 20 minutes; stay comfortably under it.
        exp: now + (19 * 60),
        aud: "appstoreconnect-v1"
      }
      JWT.encode(payload, @private_key, "ES256", { kid: @key_id, typ: "JWT" })
    end
  end
end
