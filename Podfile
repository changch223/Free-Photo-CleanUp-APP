platform :ios, '17.0'

target 'Free Photo CleanUp APP' do
  # ❌ 刪掉這行 use_frameworks!（或改成下行）
  # use_frameworks! :linkage => :static   # ← 若你需要 Swift + 靜態連結就用這行

  pod 'Google-Mobile-Ads-SDK', '~> 11.0'  # 若 11 拉不到，改 '~> 10.0'
end

post_install do |installer|
  installer.pods_project.targets.each do |t|
    t.build_configurations.each do |cfg|
      cfg.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
      cfg.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
      cfg.build_settings['GCC_TREAT_WARNINGS_AS_ERRORS'] = 'NO'
    end
  end
end
