#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Добавляет в Runner.xcodeproj расширение PacketTunnelProvider (NetworkExtension)
# и подключает файлы/энтайтлменты. Запускать на Mac:
#
#   sudo gem install xcodeproj      # один раз
#   cd ios && ruby setup_ios_extension.rb
#
# Скрипт идемпотентный — повторный запуск ничего не ломает.

require 'xcodeproj'

ROOT = __dir__
PROJECT = File.join(ROOT, 'Runner.xcodeproj')
APP_BUNDLE = 'com.example.variousVpn'
EXT_NAME = 'PacketTunnelProvider'
EXT_BUNDLE = "#{APP_BUNDLE}.PacketTunnel"
DEPLOY = '13.0'

project = Xcodeproj::Project.open(PROJECT)
runner = project.targets.find { |t| t.name == 'Runner' } or abort('Runner target не найден')

# --- 1) VPNManager.swift → в таргет Runner ---
runner_group = project.main_group['Runner'] || project.main_group.new_group('Runner', 'Runner')
unless runner.source_build_phase.files_references.any? { |f| f.display_name == 'VPNManager.swift' }
  ref = runner_group.new_reference('VPNManager.swift')
  runner.add_file_references([ref])
  puts '+ VPNManager.swift → Runner'
end

# --- 2) Энтайтлменты приложения ---
runner.build_configurations.each do |c|
  c.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end

# --- 3) Таргет расширения ---
ext = project.targets.find { |t| t.name == EXT_NAME }
if ext.nil?
  ext = project.new_target(:app_extension, EXT_NAME, :ios, DEPLOY)
  puts "+ target #{EXT_NAME}"
end

ext_group = project.main_group[EXT_NAME] || project.main_group.new_group(EXT_NAME, EXT_NAME)
%w[PacketTunnelProvider.swift XrayCore.swift LibXrayBridge.swift].each do |fname|
  next if ext.source_build_phase.files_references.any? { |f| f.display_name == fname }
  ext.add_file_references([ext_group.new_reference(fname)])
  puts "+ #{fname} → #{EXT_NAME}"
end
# Info.plist показать в дереве (не компилируется)
ext_group.new_reference('Info.plist') unless ext_group.files.any? { |f| f.display_name == 'Info.plist' }

ext.build_configurations.each do |c|
  bs = c.build_settings
  bs['PRODUCT_BUNDLE_IDENTIFIER'] = EXT_BUNDLE
  bs['INFOPLIST_FILE'] = "#{EXT_NAME}/Info.plist"
  bs['CODE_SIGN_ENTITLEMENTS'] = "#{EXT_NAME}/#{EXT_NAME}.entitlements"
  bs['SWIFT_VERSION'] = '5.0'
  bs['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOY
  # Без явного имени продукта Xcode собирает расширение в файл с пустым
  # именем — «.appex», — и сборка падает на «Multiple commands produce»:
  # несколько шагов начинают писать по одному и тому же пути.
  bs['PRODUCT_NAME'] = '$(TARGET_NAME)'
  bs['GENERATE_INFOPLIST_FILE'] = 'NO'
  bs['SKIP_INSTALL'] = 'YES'
  bs['TARGETED_DEVICE_FAMILY'] = '1,2'
  bs['CODE_SIGN_STYLE'] = 'Automatic'
end

# --- 3.1) geo-списки в ресурсы расширения ---
#
# Файлы скачивает сборка, но сами по себе в бандл они не попадут: нужна фаза
# копирования ресурсов у таргета. Искать их код будет в СВОЁМ бандле
# (Bundle.main внутри расширения — это бандл расширения), а без них Xray не
# «пропустит» правило geosite/geoip, а откажется стартовать.
res = ext.resources_build_phase
%w[geoip.dat geosite.dat].each do |fname|
  path = File.join(ROOT, EXT_NAME, fname)
  unless File.exist?(path)
    puts "= #{fname} не найден — пропускаю (скачивается на этапе сборки)"
    next
  end
  next if res.files_references.any? { |f| f.display_name == fname }
  res.add_file_reference(ext_group.new_reference(fname))
  puts "+ #{fname} → ресурсы #{EXT_NAME}"
end

# --- 4) Встраиваем расширение в приложение ---
runner.add_dependency(ext) unless runner.dependencies.any? { |d| d.target == ext }

embed = runner.copy_files_build_phases.find { |p| p.name == 'Embed App Extensions' }
if embed.nil?
  embed = runner.new_copy_files_build_phase('Embed App Extensions')
  embed.symbol_dst_subfolder_spec = :plug_ins
end
unless embed.files_references.include?(ext.product_reference)
  bf = embed.add_file_reference(ext.product_reference)
  bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
  puts '+ Embed App Extensions'
end

project.save
puts "OK. Открой Runner.xcworkspace, добавь libXray.xcframework и hev-socks5-tunnel в таргет #{EXT_NAME}, выставь Team/bundle id."
