# frozen_string_literal: true

require_relative "../lib/asc_client"
require "digest/md5"

module Fastlane
  module Actions
    # Creates/updates an App Store Connect Custom Product Page: finds-or-creates
    # the page -> version -> locale localization, sets promotional text, and
    # uploads any screenshots found under `screenshots_dir`. Never submits for
    # review — mirrors this repo's existing policy that nothing does that
    # automatically (see Fastfile header); do that manually in App Store
    # Connect (Custom Product Pages -> page -> Add for Review) once the
    # content looks right.
    class UploadCustomProductPageAction < Action
      # Best-known-current screenshotDisplayType values at write time. If ASC
      # rejects one, its error body lists the accepted enum values directly —
      # update this map with whatever it reports and re-run (idempotent:
      # already-uploaded files are skipped by name).
      DISPLAY_TYPE_BY_DEVICE = {
        "iPhone" => "APP_IPHONE_67",
        "iPad"   => "APP_IPAD_PRO_3GEN_129"
      }.freeze

      def self.run(params)
        client = ASC::Client.new
        bundle_id = params[:bundle_id] || CredentialsManager::AppfileConfig.try_fetch_value(:app_identifier)
        raise "No app_identifier — pass bundle_id: or set app_identifier in fastlane/Appfile" unless bundle_id

        app_id = find_app_id(client, bundle_id)
        page_id = find_or_create_page(client, app_id, params[:name])
        version_id = find_or_create_version(client, page_id)
        localization_id = find_or_create_localization(
          client, version_id, params[:locale], params[:promotional_text]
        )

        if params[:screenshots_dir]
          upload_screenshots(client, localization_id, params[:screenshots_dir], params[:locale])
        end

        UI.success(
          "Custom Product Page '#{params[:name]}' updated. Review it in App Store " \
          "Connect, then use Add for Review there when ready — this action never " \
          "submits for review."
        )
      end

      # MARK: - Page / version / localization

      def self.find_app_id(client, bundle_id)
        response = client.get("apps", { "filter[bundleId]" => bundle_id })
        app = response["data"]&.first
        raise "No app found for bundle id #{bundle_id}" unless app
        app["id"]
      end

      def self.find_or_create_page(client, app_id, name)
        response = client.get("apps/#{app_id}/appCustomProductPages")
        existing = response["data"]&.find { |p| p.dig("attributes", "name") == name }
        return existing["id"] if existing

        UI.message("Creating Custom Product Page '#{name}'")
        created = client.post("appCustomProductPages", {
          data: {
            type: "appCustomProductPages",
            attributes: { name: name },
            relationships: { app: { data: { type: "apps", id: app_id } } }
          }
        })
        created["data"]["id"]
      end

      def self.find_or_create_version(client, page_id)
        response = client.get("appCustomProductPages/#{page_id}/appCustomProductPageVersions")
        existing = response["data"]&.first
        return existing["id"] if existing

        UI.message("Creating Custom Product Page version")
        created = client.post("appCustomProductPageVersions", {
          data: {
            type: "appCustomProductPageVersions",
            relationships: {
              appCustomProductPage: { data: { type: "appCustomProductPages", id: page_id } }
            }
          }
        })
        created["data"]["id"]
      end

      def self.find_or_create_localization(client, version_id, locale, promotional_text)
        response = client.get("appCustomProductPageVersions/#{version_id}/appCustomProductPageLocalizations")
        existing = response["data"]&.find { |l| l.dig("attributes", "locale") == locale }

        if existing
          if promotional_text
            client.patch("appCustomProductPageLocalizations/#{existing['id']}", {
              data: {
                type: "appCustomProductPageLocalizations",
                id: existing["id"],
                attributes: { promotionalText: promotional_text }
              }
            })
          end
          return existing["id"]
        end

        UI.message("Creating '#{locale}' localization")
        created = client.post("appCustomProductPageLocalizations", {
          data: {
            type: "appCustomProductPageLocalizations",
            attributes: { locale: locale, promotionalText: promotional_text }.compact,
            relationships: {
              appCustomProductPageVersion: { data: { type: "appCustomProductPageVersions", id: version_id } }
            }
          }
        })
        created["data"]["id"]
      end

      # MARK: - Screenshots
      # fastlane `snapshot` lays files out as <output_dir>/<device>/<locale>/<name>.png

      def self.upload_screenshots(client, localization_id, screenshots_dir, locale)
        pattern = File.join(screenshots_dir, "*", locale, "*.png")
        by_device = Dir.glob(pattern).group_by { |path| File.basename(File.dirname(File.dirname(path))) }

        if by_device.empty?
          UI.important("No screenshots found matching #{pattern}")
          return
        end

        by_device.each do |device, paths|
          display_type = DISPLAY_TYPE_BY_DEVICE.find { |prefix, _| device.include?(prefix) }&.last
          unless display_type
            UI.important("No screenshotDisplayType mapping for device '#{device}' — skipping #{paths.size} file(s)")
            next
          end

          set_id = find_or_create_screenshot_set(client, localization_id, display_type)
          existing_names = existing_screenshot_names(client, set_id)

          paths.sort.each do |path|
            filename = File.basename(path)
            if existing_names.include?(filename)
              UI.message("Skipping already-uploaded #{filename}")
              next
            end
            upload_screenshot(client, set_id, path)
          end
        end
      end

      def self.find_or_create_screenshot_set(client, localization_id, display_type)
        response = client.get("appCustomProductPageLocalizations/#{localization_id}/appScreenshotSets")
        existing = response["data"]&.find { |s| s.dig("attributes", "screenshotDisplayType") == display_type }
        return existing["id"] if existing

        UI.message("Creating screenshot set for #{display_type}")
        created = client.post("appScreenshotSets", {
          data: {
            type: "appScreenshotSets",
            attributes: { screenshotDisplayType: display_type },
            relationships: {
              appCustomProductPageLocalization: {
                data: { type: "appCustomProductPageLocalizations", id: localization_id }
              }
            }
          }
        })
        created["data"]["id"]
      end

      def self.existing_screenshot_names(client, set_id)
        response = client.get("appScreenshotSets/#{set_id}/appScreenshots")
        (response["data"] || []).map { |s| s.dig("attributes", "fileName") }
      end

      # Reserve -> upload bytes to the pre-signed URL(s) -> commit. Same
      # mechanism the regular App Store version screenshot upload uses.
      def self.upload_screenshot(client, set_id, path)
        data = File.binread(path)
        UI.message("Uploading #{File.basename(path)} (#{data.bytesize} bytes)")

        reserved = client.post("appScreenshots", {
          data: {
            type: "appScreenshots",
            attributes: { fileName: File.basename(path), fileSize: data.bytesize },
            relationships: {
              appScreenshotSet: { data: { type: "appScreenshotSets", id: set_id } }
            }
          }
        })

        screenshot = reserved["data"]
        (screenshot.dig("attributes", "uploadOperations") || []).each do |op|
          chunk = data.byteslice(op["offset"], op["length"])
          client.put_raw(op["url"], op["requestHeaders"] || [], chunk)
        end

        checksum = Digest::MD5.hexdigest(data)
        client.patch("appScreenshots/#{screenshot['id']}", {
          data: {
            type: "appScreenshots",
            id: screenshot["id"],
            attributes: { uploaded: true, sourceFileChecksum: checksum }
          }
        })
      end

      # MARK: - Fastlane action metadata

      def self.description
        "Creates/updates an App Store Connect Custom Product Page's screenshots + promotional text (does not submit for review)"
      end

      def self.authors
        ["bluefunda"]
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :name,
            description: "Internal name of the Custom Product Page (never shown to users)",
            optional: false,
            type: String
          ),
          FastlaneCore::ConfigItem.new(
            key: :locale,
            description: "Locale for the localization",
            optional: true,
            default_value: "en-US",
            type: String
          ),
          FastlaneCore::ConfigItem.new(
            key: :promotional_text,
            description: "Promotional text for this locale",
            optional: true,
            type: String
          ),
          FastlaneCore::ConfigItem.new(
            key: :screenshots_dir,
            description: "Directory containing <device>/<locale>/*.png screenshots, e.g. fastlane/screenshots_ios_raw/chat",
            optional: true,
            type: String
          ),
          FastlaneCore::ConfigItem.new(
            key: :bundle_id,
            description: "App bundle id — defaults to Appfile's app_identifier",
            optional: true,
            type: String
          )
        ]
      end

      def self.is_supported?(platform)
        platform == :ios
      end
    end
  end
end
