//
//  AppOpenAdManager.swift
//  Free Photo CleanUp APP
//
//  Created by chang chiawei on 2025-08-10.
//

import GoogleMobileAds
import UIKit

class AppOpenAdManager: NSObject, FullScreenContentDelegate {
    static let shared = AppOpenAdManager()
    
    private var appOpenAd: AppOpenAd? // 廣告實體
    private var isLoadingAd = false  // 是否正在載入中
    private var isAdBeingShown = false // 廣告是否正在顯示中
    private let adUnitID = "ca-app-pub-9275380963550837/7469163929"
    
    func loadAd() {
        guard !isLoadingAd else { return }
        isLoadingAd = true
        print("Start loading App Open Ad...")

        AppOpenAd.load(
            with: adUnitID,
            request: Request(),
            completionHandler: { [weak self] (ad: AppOpenAd?, error: Error?) in
                self?.isLoadingAd = false
                if let error = error {
                    print("❌ Failed to load app open ad: \(error.localizedDescription)")
                    return
                }
                self?.appOpenAd = ad
                self?.appOpenAd?.fullScreenContentDelegate = self // ★ 這裡就設好，不要在 show 的時候設

                print("✅ App open ad loaded successfully")
                self?.showAdIfAvailable() // ★ 下載完成後馬上嘗試顯示
            }
        )
    }
    
    func showAdIfAvailable() {
        guard let ad = appOpenAd,
              let windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController,
              !isAdBeingShown else {
            print("⚠️ No ad ready or ad is already being shown.")
            return
        }

        print("🚀 Presenting App Open Ad")
        isAdBeingShown = true
        ad.present(from: rootVC)
        appOpenAd = nil // ★ 顯示完就清掉，避免重複使用
    }
}

// MARK: - GADFullScreenContentDelegate
extension AppOpenAdManager {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        isAdBeingShown = false
        print("🌀 App Open Ad dismissed, ready to load next one.")
        //loadAd() // ★ 廣告關閉後重新 load 下一支
    }
}
