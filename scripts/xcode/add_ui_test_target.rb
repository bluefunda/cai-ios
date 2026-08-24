#!/usr/bin/env ruby
# frozen_string_literal: true

# One-time script: adds the CAIUITests UI Testing Bundle target to
# CAI.xcodeproj, hosted by the CAI app target, and wires it into the CAI
# scheme's Test action so `fastlane snapshot` (only_testing: ["CAIUITests"])
# can build and run it. Idempotent — safe to re-run after adding new files
# under CAIUITests/.
#
# Run with: bundle exec ruby scripts/xcode/add_ui_test_target.rb

require "xcodeproj"

PROJECT_PATH = File.expand_path("../../CAI.xcodeproj", __dir__)
UI_TESTS_DIR = File.expand_path("../../CAIUITests", __dir__)
TARGET_NAME = "CAIUITests"
HOST_TARGET_NAME = "CAI"

project = Xcodeproj::Project.open(PROJECT_PATH)
app_target = project.targets.find { |t| t.name == HOST_TARGET_NAME }
raise "#{HOST_TARGET_NAME} target not found in #{PROJECT_PATH}" unless app_target

host_config = app_target.build_configurations.first.build_settings
# IPHONEOS_DEPLOYMENT_TARGET/SWIFT_VERSION live at the project level here (the
# CAI target inherits them rather than overriding), so read project-level
# configs too rather than assuming the target-level hash has them — an empty
# string override on the new target silently breaks the test-bundle build.
project_config = project.build_configurations.first.build_settings

ui_test_target = project.targets.find { |t| t.name == TARGET_NAME }

if ui_test_target.nil?
  ui_test_target = project.new_target(:ui_test_bundle, TARGET_NAME, :ios)
  ui_test_target.add_dependency(app_target)

  ui_test_target.build_configurations.each do |config|
    config.build_settings["PRODUCT_NAME"] = "$(TARGET_NAME)"
    config.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.bluefunda.ai.uitests"
    config.build_settings["TEST_TARGET_NAME"] = HOST_TARGET_NAME
    config.build_settings["CODE_SIGN_STYLE"] = "Automatic"
    config.build_settings["GENERATE_INFOPLIST_FILE"] = "YES"
    config.build_settings["SWIFT_VERSION"] = host_config["SWIFT_VERSION"] || project_config["SWIFT_VERSION"] || "5.0"
    config.build_settings["TARGETED_DEVICE_FAMILY"] = "1,2"
    # Deliberately NOT setting IPHONEOS_DEPLOYMENT_TARGET — leave it
    # inherited from the project-level config, same as the CAI target does.
  end

  puts "Created target #{TARGET_NAME}"
else
  puts "Target #{TARGET_NAME} already exists — syncing files only"
end

# --- Source files: add any *.swift under CAIUITests/ not already in the target

group = project.main_group[TARGET_NAME] || project.main_group.new_group(TARGET_NAME, UI_TESTS_DIR)

existing_source_paths = ui_test_target.source_build_phase.files.map { |f| f.file_ref&.real_path.to_s }

Dir.glob(File.join(UI_TESTS_DIR, "*.swift")).sort.each do |path|
  next if existing_source_paths.include?(File.realpath(path))

  file_ref = group.files.find { |f| f.real_path.to_s == File.realpath(path) } ||
             group.new_reference(path)
  ui_test_target.add_file_references([file_ref])
  puts "Added source file: #{File.basename(path)}"
end

# --- Scheme: add CAIUITests as a testable under the CAI scheme's Test action

scheme_path = Xcodeproj::XCScheme.shared_data_dir(PROJECT_PATH) + "#{HOST_TARGET_NAME}.xcscheme"
scheme = Xcodeproj::XCScheme.new(scheme_path.to_s)

already_testable = scheme.test_action.testables.any? do |t|
  t.buildable_references.first&.target_name == TARGET_NAME
end

unless already_testable
  test_ref = Xcodeproj::XCScheme::TestAction::TestableReference.new(ui_test_target)
  scheme.test_action.add_testable(test_ref)
  scheme.save!
  puts "Added #{TARGET_NAME} to #{HOST_TARGET_NAME} scheme's Test action"
end

project.save
puts "Saved #{PROJECT_PATH}"
