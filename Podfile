platform :ios, '17.0'

target 'Free Photo CleanUp APP' do
  use_frameworks! :linkage => :static   # 建議；不想用可刪
  pod 'Google-Mobile-Ads-SDK', '~> 11.0'
end

post_install do |installer|
  installer.pods_project.targets.each do |t|
    t.build_configurations.each do |cfg|
      cfg.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'   # ← 統一成 17.0
      cfg.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
      cfg.build_settings['GCC_TREAT_WARNINGS_AS_ERRORS'] = 'NO'
    end
  end
end
