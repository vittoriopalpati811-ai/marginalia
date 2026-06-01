#!/usr/bin/env ruby
# frozen_string_literal: true
#
# add_watch_targets.rb
# ─────────────────────────────────────────────────────────────────────────────
# Injects the Apple Watch app + its WidgetKit complication extension into the
# iOS Xcode project that `flutter create` regenerates on every Codemagic build
# (Flutter does not generate watchOS targets). Mirrors add_widgets_extension.rb
# but for watchOS:
#
#   • MarginaliaWatch            — watchOS app (single-target SwiftUI)
#       bundle id io.marginalia.app.watchkitapp
#   • MarginaliaWatchWidgets     — watchOS WidgetKit complication extension
#       bundle id io.marginalia.app.watchkitapp.MarginaliaWatchWidgets
#
# Embedding:
#   • the complication extension is embedded into the WATCH app (PlugIns)
#   • the watch app is embedded into the iOS app (Runner) "Embed Watch Content"
#
# Run from repo root AFTER `flutter create` + bundle-id normalization and BEFORE
# `pod install`:  ruby ios/scripts/add_watch_targets.rb
# Idempotent.

require 'xcodeproj'

PROJECT_PATH = 'ios/Runner.xcodeproj'
APP_TARGET   = 'Runner'
TEAM_ID      = '6J8VDXZ9K8'
DEPLOY       = '10.0'

WATCH_NAME   = 'MarginaliaWatch'
WATCH_BUNDLE = 'io.marginalia.app.watchkitapp'
WATCH_DIR    = 'MarginaliaWatch'

EXT_NAME     = 'MarginaliaWatchWidgets'
EXT_BUNDLE   = 'io.marginalia.app.watchkitapp.MarginaliaWatchWidgets'
EXT_DIR      = 'MarginaliaWatchWidgets'

abort("✗ #{PROJECT_PATH} not found") unless File.exist?(PROJECT_PATH)
project = Xcodeproj::Project.open(PROJECT_PATH)

if project.targets.any? { |t| t.name == WATCH_NAME }
  puts "✓ #{WATCH_NAME} already present — nothing to do"
  exit 0
end

runner = project.targets.find { |t| t.name == APP_TARGET }
abort("✗ Could not find #{APP_TARGET} target") if runner.nil?

# ── Watch app target ──────────────────────────────────────────────────────────
puts "→ Creating watchOS app target #{WATCH_NAME} (#{WATCH_BUNDLE})"
watch_app = project.new_target(:application, WATCH_NAME, :watchos, DEPLOY, nil, :swift)

watch_group = project.main_group.new_group(WATCH_DIR, WATCH_DIR)
watch_src   = watch_group.new_file('MarginaliaWatchApp.swift')
watch_group.new_file('Info.plist')
watch_group.new_file('MarginaliaWatch.entitlements')
watch_app.add_file_references([watch_src])

# Watch app icon (App Store upload requires it — ITMS-90391/90713).
assets_ref = watch_group.new_file('Assets.xcassets')
watch_app.add_resources([assets_ref])

watch_app.build_configurations.each do |c|
  c.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER'  => WATCH_BUNDLE,
    'PRODUCT_NAME'               => '$(TARGET_NAME)',
    'SDKROOT'                    => 'watchos',
    'SUPPORTED_PLATFORMS'        => 'watchos watchsimulator',
    'WATCHOS_DEPLOYMENT_TARGET'  => DEPLOY,
    'TARGETED_DEVICE_FAMILY'     => '4',
    'INFOPLIST_FILE'             => "#{WATCH_DIR}/Info.plist",
    'CODE_SIGN_ENTITLEMENTS'     => "#{WATCH_DIR}/MarginaliaWatch.entitlements",
    'GENERATE_INFOPLIST_FILE'    => 'NO',
    'SWIFT_VERSION'              => '5.0',
    'SKIP_INSTALL'               => 'YES',
    'CURRENT_PROJECT_VERSION'    => '1',
    'MARKETING_VERSION'          => '1.0.0',
    'DEVELOPMENT_TEAM'           => TEAM_ID,
    'CODE_SIGN_STYLE'            => 'Manual',
    'ASSETCATALOG_COMPILER_APPICON_NAME' => 'AppIcon',
    'SUPPORTS_MACCATALYST'       => 'NO',
    'LD_RUNPATH_SEARCH_PATHS'    => '$(inherited) @executable_path/Frameworks'
  )
end

# ── Watch widget (complication) extension target ──────────────────────────────
puts "→ Creating watchOS widget extension #{EXT_NAME} (#{EXT_BUNDLE})"
watch_ext = project.new_target(:app_extension, EXT_NAME, :watchos, DEPLOY, nil, :swift)

ext_group = project.main_group.new_group(EXT_DIR, EXT_DIR)
ext_src   = ext_group.new_file('MarginaliaWatchWidgets.swift')
ext_group.new_file('Info.plist')
ext_group.new_file('MarginaliaWatchWidgets.entitlements')
watch_ext.add_file_references([ext_src])

watch_ext.build_configurations.each do |c|
  c.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER'  => EXT_BUNDLE,
    'PRODUCT_NAME'               => '$(TARGET_NAME)',
    'SDKROOT'                    => 'watchos',
    'SUPPORTED_PLATFORMS'        => 'watchos watchsimulator',
    'WATCHOS_DEPLOYMENT_TARGET'  => DEPLOY,
    'TARGETED_DEVICE_FAMILY'     => '4',
    'INFOPLIST_FILE'             => "#{EXT_DIR}/Info.plist",
    'CODE_SIGN_ENTITLEMENTS'     => "#{EXT_DIR}/MarginaliaWatchWidgets.entitlements",
    'GENERATE_INFOPLIST_FILE'    => 'NO',
    'SWIFT_VERSION'              => '5.0',
    'SKIP_INSTALL'               => 'YES',
    'CURRENT_PROJECT_VERSION'    => '1',
    'MARKETING_VERSION'          => '1.0.0',
    'DEVELOPMENT_TEAM'           => TEAM_ID,
    'CODE_SIGN_STYLE'            => 'Manual',
    'LD_RUNPATH_SEARCH_PATHS'    => '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks'
  )
end

# ── Embed the complication extension into the WATCH app (PlugIns) ─────────────
watch_app.add_dependency(watch_ext)
embed_ext = watch_app.new_copy_files_build_phase('Embed Foundation Extensions')
embed_ext.symbol_dst_subfolder_spec = :plug_ins
bf_ext = embed_ext.add_file_reference(watch_ext.product_reference, true)
bf_ext.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

# ── Embed the WATCH app into the iOS app (Runner) "Embed Watch Content" ───────
# dstSubfolderSpec 16 = products directory; dstPath = "$(CONTENTS_FOLDER_PATH)/Watch"
runner.add_dependency(watch_app)
embed_watch = runner.new_copy_files_build_phase('Embed Watch Content')
embed_watch.dst_subfolder_spec = '16'
embed_watch.dst_path = '$(CONTENTS_FOLDER_PATH)/Watch'
bf_watch = embed_watch.add_file_reference(watch_app.product_reference, true)
bf_watch.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

# Keep "Embed Watch Content" before the Flutter "Thin Binary" run-script to avoid
# the "Cycle inside Runner" deadlock (same fix as the iOS widget embed phase).
order = runner.build_phases.to_a
order.delete(embed_watch)
fw_index = order.find_index { |p| p.isa == 'PBXFrameworksBuildPhase' }
order.insert(fw_index ? fw_index + 1 : order.length, embed_watch)
order.each { |p| runner.build_phases.delete(p) }
order.each { |p| runner.build_phases << p }

project.save

puts "✓ Injected watch app + complication extension"
puts "  targets now : #{project.targets.map(&:name).join(', ')}"
puts "  runner phases: #{runner.build_phases.map(&:display_name).join(' > ')}"
[watch_app, watch_ext].each do |t|
  rel = t.build_configurations.find { |c| c.name == 'Release' } || t.build_configurations.first
  bs = rel.build_settings
  puts "  #{t.name}: SDKROOT=#{bs['SDKROOT']} SUPPORTED_PLATFORMS=#{bs['SUPPORTED_PLATFORMS']} WATCHOS_DEPLOYMENT_TARGET=#{bs['WATCHOS_DEPLOYMENT_TARGET']}"
end
