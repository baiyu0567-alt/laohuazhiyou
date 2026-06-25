require 'xcodeproj'

PROJECT_PATH = 'PresbyFriend/PresbyFriend.xcodeproj'
EXTENSION_NAME = 'ShareExtension'
EXTENSION_SOURCE_DIR = '../../ShareExtension'

project = Xcodeproj::Project.open(PROJECT_PATH)
main_target = project.targets.first
main_group = project.main_group.find_subpath('PresbyFriend', false)

# ── 1. Create source group for ShareExtension files ──
ext_group = main_group.new_group(EXTENSION_NAME, EXTENSION_SOURCE_DIR)
ext_group.source_tree = '<group>'

# ── 2. Create Shared source group (SettingsModel shared between targets) ──
shared_group = main_group.find_subpath('Shared', false) || main_group.new_group('Shared', '../../Shared')

# ── 3. Create extension target ──
ext_target = project.new_target(
  :app_extension,
  EXTENSION_NAME,
  :ios,
  nil  # use default deployment target from project
)
ext_target.product_name = EXTENSION_NAME

# ── 4. Configure extension build settings ──
['Debug', 'Release'].each do |config_name|
  config = ext_target.build_configuration_list[config_name]
  settings = config.build_settings
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.presbyfriend.share-extension'
  settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  settings['MARKETING_VERSION'] = '1.0'
  settings['CURRENT_PROJECT_VERSION'] = '1'
  settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  settings['INFOPLIST_KEY_CFBundleDisplayName'] = 'PresbyFriend'
  settings['INFOPLIST_KEY_NSHumanReadableCopyright'] = ''
  settings['CODE_SIGN_STYLE'] = 'Automatic'
  settings['SWIFT_VERSION'] = '5.0'
  settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  settings['SWIFT_APPROACHABLE_CONCURRENCY'] = 'YES'
  settings['SWIFT_DEFAULT_ACTOR_ISOLATION'] = 'MainActor'
  settings['LD_RUNPATH_SEARCH_PATHS'] = '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks'
  # Link against Foundation and SwiftUI
  settings['OTHER_LDFLAGS'] = '$(inherited)'
end

# ── 5. Add App Group entitlement ──
ext_target.add_system_framework('Foundation')
ext_target.add_system_framework('SwiftUI')

# ── 6. Save ──
project.save
puts "✅ Share Extension target '#{EXTENSION_NAME}' added successfully."
puts "   Bundle ID: com.presbyfriend.share-extension"
puts "   Source: #{EXTENSION_SOURCE_DIR}"
