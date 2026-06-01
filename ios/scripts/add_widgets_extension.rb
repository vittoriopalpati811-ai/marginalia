#!/usr/bin/env ruby
# frozen_string_literal: true
#
# add_widgets_extension.rb
# ─────────────────────────────────────────────────────────────────────────────
# Injects the "MarginaliaWidgetsExtension" WidgetKit app-extension target into
# the iOS Xcode project that `flutter create` regenerates on every Codemagic
# build. The target, its source, Info.plist, entitlements and the host app's
# "Embed App Extensions" phase cannot be committed (the .xcodeproj is generated
# in CI), so we re-create them here with the `xcodeproj` gem that ships with
# CocoaPods on the Mac runner.
#
# Run from the repo root, AFTER `flutter create` + bundle-id normalization and
# BEFORE `pod install`:  ruby ios/scripts/add_widgets_extension.rb
#
# Idempotent: if the target already exists it does nothing.

require 'xcodeproj'

PROJECT_PATH = 'ios/Runner.xcodeproj'
EXT_NAME     = 'MarginaliaWidgetsExtension'
EXT_BUNDLE   = 'io.marginalia.app.MarginaliaWidgets'
APP_TARGET   = 'Runner'
TEAM_ID      = '6J8VDXZ9K8'
DEPLOYMENT   = '17.0'
GROUP_DIR    = 'MarginaliaWidgets' # relative to ios/ (project SOURCE_ROOT)

abort("✗ #{PROJECT_PATH} not found — run after `flutter create`") unless File.exist?(PROJECT_PATH)

project = Xcodeproj::Project.open(PROJECT_PATH)

if project.targets.any? { |t| t.name == EXT_NAME }
  puts "✓ #{EXT_NAME} already present — nothing to do"
  exit 0
end

runner = project.targets.find { |t| t.name == APP_TARGET }
abort("✗ Could not find the #{APP_TARGET} target") if runner.nil?

puts "→ Creating app-extension target #{EXT_NAME} (#{EXT_BUNDLE})"
ext = project.new_target(:app_extension, EXT_NAME, :ios, DEPLOYMENT, nil, :swift)

# ── Source / Info.plist / entitlements file references ───────────────────────
# new_group(name, path): path is relative to the main group (the project dir,
# i.e. ios/), source tree :group. new_file(basename) then resolves to
# ios/MarginaliaWidgets/<basename> — the robust, path-doubling-proof pattern.
group = project.main_group.new_group(GROUP_DIR, GROUP_DIR)

swift_ref = group.new_file('MarginaliaWidgets.swift')
group.new_file('Info.plist')
group.new_file('MarginaliaWidgets.entitlements')

ext.add_file_references([swift_ref]) # routed to the Sources (compile) phase

# ── Build settings (Debug + Release) ─────────────────────────────────────────
ext.build_configurations.each do |config|
  config.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER'      => EXT_BUNDLE,
    'PRODUCT_NAME'                   => '$(TARGET_NAME)',
    'INFOPLIST_FILE'                 => "#{GROUP_DIR}/Info.plist",
    'CODE_SIGN_ENTITLEMENTS'         => "#{GROUP_DIR}/MarginaliaWidgets.entitlements",
    'GENERATE_INFOPLIST_FILE'        => 'NO',
    'IPHONEOS_DEPLOYMENT_TARGET'     => DEPLOYMENT,
    'SWIFT_VERSION'                  => '5.0',
    'TARGETED_DEVICE_FAMILY'         => '1,2',
    'SKIP_INSTALL'                   => 'YES',
    'CURRENT_PROJECT_VERSION'        => '1',
    'MARKETING_VERSION'              => '1.0.0',
    'DEVELOPMENT_TEAM'               => TEAM_ID,
    'CODE_SIGN_STYLE'                => 'Manual',
    'SWIFT_OPTIMIZATION_LEVEL'       => (config.name == 'Debug' ? '-Onone' : '-O'),
    'LD_RUNPATH_SEARCH_PATHS'        => '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks',
    'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME' => 'AccentColor'
  )
  # No asset catalog in the extension — drop the accent-color setting so the
  # build doesn't warn about a missing AccentColor asset.
  config.build_settings.delete('ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME')
end

# ── Embed the extension into the host app ────────────────────────────────────
runner.add_dependency(ext)

embed = runner.copy_files_build_phases.find { |p| p.symbol_dst_subfolder_spec == :plug_ins }
embed ||= runner.new_copy_files_build_phase('Embed App Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
embed.dst_path = ''

build_file = embed.add_file_reference(ext.product_reference, true)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

# The target dependency added above guarantees the extension builds before the
# host app's embed phase runs; no manual phase reordering needed.

project.save

puts "✓ Injected #{EXT_NAME}"
puts "  bundle id        : #{EXT_BUNDLE}"
puts "  source           : #{GROUP_DIR}/MarginaliaWidgets.swift"
puts "  embedded in       : #{APP_TARGET} (Embed App Extensions phase)"
puts "  targets now       : #{project.targets.map(&:name).join(', ')}"
