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
WDG_NAME = 'VariousWidgets'
WDG_BUNDLE = "#{APP_BUNDLE}.Widgets"
DEPLOY = '13.0'

# Версия берётся из pubspec.yaml — единственного места, где её правят.
# Формат «1.0.0+1»: до плюса — версия для человека, после — номер сборки.
pubspec = File.read(File.join(ROOT, '..', 'pubspec.yaml'))
version_line = pubspec[/^version:\s*(\S+)/, 1] || '1.0.0+1'
BUILD_NAME, BUILD_NUMBER = version_line.split('+')
BUILD_NUMBER ||= '1'

project = Xcodeproj::Project.open(PROJECT)
runner = project.targets.find { |t| t.name == 'Runner' } or abort('Runner target не найден')

# --- 1) VPNManager.swift → в таргет Runner ---
runner_group = project.main_group['Runner'] || project.main_group.new_group('Runner', 'Runner')
%w[VPNManager.swift LiveActivityBridge.swift].each do |fname|
  next if runner.source_build_phase.files_references.any? { |f| f.display_name == fname }
  runner.add_file_references([runner_group.new_reference(fname)])
  puts "+ #{fname} → Runner"
end

# --- 1.1) Запасные значки приложения ---
#
# Система берёт их ГОТОВЫМИ файлами из корня бандла по имени из Info.plist —
# в отличие от Android, где подменяется алиас activity. Значит все варианты
# обязаны попасть в ресурсы приложения заранее.
alt_dir = File.join(ROOT, 'Runner', 'AltIcons')
if File.directory?(alt_dir)
  alt_group = runner_group['AltIcons'] || runner_group.new_group('AltIcons', 'AltIcons')
  app_res = runner.resources_build_phase
  Dir.children(alt_dir).sort.each do |fname|
    next unless fname.end_with?('.png')
    next if app_res.files_references.any? { |f| f.display_name == fname }
    app_res.add_file_reference(alt_group.new_reference(fname))
  end
  puts "+ запасные значки → ресурсы Runner (#{Dir.children(alt_dir).size} файлов)"
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

puts "= версия расширения: #{BUILD_NAME} (#{BUILD_NUMBER})"

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
  # Info.plist расширения ссылается на эти переменные, но Flutter объявляет их
  # только для основного приложения. Без них версия расширения пустая, и iOS
  # отказывается его устанавливать: «bundleVersion must be set».
  bs['FLUTTER_BUILD_NAME'] = BUILD_NAME
  bs['FLUTTER_BUILD_NUMBER'] = BUILD_NUMBER
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

# --- 3.2) Ядро Xray: подключаем xcframework ---
#
# Файл скачивает сборка (см. шаг «Скачать ядро Xray» в CI). Без линковки
# `#if canImport(LibXray)` в XrayCore.swift выбирает пустую ветку: расширение
# соберётся, туннель поднимется, а трафика не будет — самая обидная поломка,
# потому что внешне всё выглядит рабочим.
fw_path = File.join(ROOT, EXT_NAME, 'LibXray.xcframework')
if File.directory?(fw_path)
  fw_ref = ext_group.files.find { |f| f.display_name == 'LibXray.xcframework' } ||
           ext_group.new_reference('LibXray.xcframework')
  frameworks = ext.frameworks_build_phase
  unless frameworks.files_references.include?(fw_ref)
    frameworks.add_file_reference(fw_ref)
    puts '+ LibXray.xcframework → линковка расширения'
  end
  ext.build_configurations.each do |c|
    c.build_settings['FRAMEWORK_SEARCH_PATHS'] =
      ['$(inherited)', "$(PROJECT_DIR)/#{EXT_NAME}"]
  end
else
  puts '! LibXray.xcframework не найден — расширение соберётся без ядра'
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

# --- 5) Встраивание расширения — ДО шага «Thin Binary» ---
#
# Иначе Xcode отказывается собирать с «Cycle inside Runner»: копирование
# расширения ждёт «Thin Binary», тот читает готовый Info.plist приложения, а
# Info.plist собирается уже после копирования — круг замкнут.
#
# «Thin Binary» — шаг самого Flutter, он подчищает собранный бандл, поэтому
# всё, что кладётся внутрь приложения, обязано попасть туда раньше.
phases = runner.build_phases
thin = phases.find { |ph| ph.respond_to?(:name) && ph.name.to_s.include?('Thin Binary') }
if thin
  ti = phases.index(thin)
  ei = phases.index(embed)
  if ti && ei && ei > ti
    # Разные версии xcodeproj дают разный набор методов у списка фаз, а
    # проверить это без Mac нельзя. Пробуем по очереди и не роняем скрипт:
    # если переставить не вышло, лучше собрать с прежним порядком и увидеть
    # понятную ошибку, чем оборваться здесь без объяснений.
    moved = false
    begin
      phases.move(embed, ti)
      moved = true
    rescue NoMethodError, ArgumentError
      begin
        phases.delete(embed)
        phases.insert(ti, embed)
        moved = true
      rescue NoMethodError, ArgumentError => e
        puts "! переставить фазу не удалось: #{e.class}"
      end
    end
    puts '~ Embed App Extensions поднят выше Thin Binary' if moved
  end
else
  puts '= шаг Thin Binary не найден — порядок оставлен как есть'
end

# --- 6) Расширение виджетов: домашний экран + Dynamic Island ---
#
# Отдельный таргет, а не часть туннеля: система запускает виджеты своим
# процессом и по своему поводу, а расширение VPN обязано жить ровно столько,
# сколько поднят туннель. Смешивать их нельзя.
wdg_group = project.main_group[WDG_NAME] || project.main_group.new_group(WDG_NAME, WDG_NAME)
wdg = project.targets.find { |t| t.name == WDG_NAME }
if wdg.nil?
  wdg = project.new_target(:app_extension, WDG_NAME, :ios, '14.0')
  puts "+ target #{WDG_NAME}"
end

%w[VariousWidgetsBundle.swift StatusWidget.swift VpnState.swift Palette.swift
   VpnActivityAttributes.swift VpnLiveActivity.swift].each do |fname|
  next if wdg.source_build_phase.files_references.any? { |f| f.display_name == fname }
  wdg.add_file_references([wdg_group.new_reference(fname)])
  puts "+ #{fname} → #{WDG_NAME}"
end
wdg_group.new_reference('Info.plist') unless wdg_group.files.any? { |f| f.display_name == 'Info.plist' }

# Описание живого события компилируется И в приложение: система сопоставляет
# запущенное событие с его оформлением по имени типа, а типы из чужого
# расширения приложению не видны. Без этой строки остров просто не появится.
attrs = 'VpnActivityAttributes.swift'
unless runner.source_build_phase.files_references.any? { |f| f.display_name == attrs }
  ref = wdg_group.files.find { |f| f.display_name == attrs } || wdg_group.new_reference(attrs)
  runner.add_file_references([ref])
  puts "+ #{attrs} → Runner"
end

wdg.build_configurations.each do |c|
  bs = c.build_settings
  bs['PRODUCT_BUNDLE_IDENTIFIER'] = WDG_BUNDLE
  bs['INFOPLIST_FILE'] = "#{WDG_NAME}/Info.plist"
  bs['CODE_SIGN_ENTITLEMENTS'] = "#{WDG_NAME}/#{WDG_NAME}.entitlements"
  bs['SWIFT_VERSION'] = '5.0'
  # Виджеты появились в iOS 14, живое событие — в 16.1. Нижнюю планку держим
  # на 14: код версии проверяет сам, а расширение с более высоким минимумом
  # просто не поставится на часть телефонов.
  bs['IPHONEOS_DEPLOYMENT_TARGET'] = '14.0'
  bs['PRODUCT_NAME'] = '$(TARGET_NAME)'
  bs['FLUTTER_BUILD_NAME'] = BUILD_NAME
  bs['FLUTTER_BUILD_NUMBER'] = BUILD_NUMBER
  bs['GENERATE_INFOPLIST_FILE'] = 'NO'
  bs['SKIP_INSTALL'] = 'YES'
  bs['TARGETED_DEVICE_FAMILY'] = '1,2'
  bs['CODE_SIGN_STYLE'] = 'Automatic'
  # Расширению виджетов нужен SwiftUI-«главный» тип, а не main.swift.
  bs['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] ||= '$(inherited)'
end

runner.add_dependency(wdg) unless runner.dependencies.any? { |d| d.target == wdg }
unless embed.files_references.include?(wdg.product_reference)
  bf = embed.add_file_reference(wdg.product_reference)
  bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
  puts '+ VariousWidgets → Embed App Extensions'
end

# --- 7) Разрешение на живые события ---
#
# Без этого ключа система молча не покажет ни острова, ни карточки на экране
# блокировки — и разбираться будет не в чем: ошибок не будет тоже.
app_plist = File.join(ROOT, 'Runner', 'Info.plist')
plist = File.read(app_plist)
unless plist.include?('NSSupportsLiveActivities')
  plist = plist.sub('<dict>', "<dict>
	<key>NSSupportsLiveActivities</key>
	<true/>")
  File.write(app_plist, plist)
  puts '+ NSSupportsLiveActivities → Runner/Info.plist'
end

project.save
puts "OK. Открой Runner.xcworkspace, добавь libXray.xcframework и hev-socks5-tunnel в таргет #{EXT_NAME}, выставь Team/bundle id."
