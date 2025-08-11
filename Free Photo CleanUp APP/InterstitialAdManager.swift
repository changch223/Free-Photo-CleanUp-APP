//
//  InterstitialAdManager.swift
//  Free Photo CleanUp APP
//
//  Created by chang chiawei on 2025-08-10.
//

import UIKit
import GoogleMobileAds

/// 單例：插頁廣告（Interstitial）
final class InterstitialAdManager: NSObject, FullScreenContentDelegate {
    static let shared = InterstitialAdManager()

    // MARK: - 廣告 ID 切換
    #if DEBUG
    /// 測試模式廣告 ID（Google 官方提供）
    private let adUnitID = "ca-app-pub-3940256099942544/4411468910"
    private let isDebugMode = true
    #else
    /// 真實廣告 ID
    private let adUnitID = "ca-app-pub-9275380963550837/7469163929"
    private let isDebugMode = false
    #endif

    private var ad: InterstitialAd?
    private var isLoading = false

    /// 頻率控制（避免過度打擾）
    private var lastShownAt: Date = .distantPast
    private let cooldown: TimeInterval = 25   // 秒：一次顯示後至少隔 25 秒

    // MARK: Load
    func preload() {
        guard !isLoading, ad == nil else { return }
        isLoading = true

        if isDebugMode {
            print("🛠 [DEBUG] Using Test Ad Unit ID: \(adUnitID)")
        }

        InterstitialAd.load(with: adUnitID, request: Request()) { [weak self] ad, error in
            guard let self else { return }
            self.isLoading = false
            if let error = error {
                print("❌ Interstitial load failed:", error.localizedDescription)
                return
            }
            self.ad = ad
            self.ad?.fullScreenContentDelegate = self
            print("✅ Interstitial loaded")
        }
    }

    // MARK: Present
    /// 嘗試顯示；若未準備好就直接執行 completion
    func showIfReady(from viewController: UIViewController, completion: (() -> Void)? = nil) {
        // 頻率控制
        if Date().timeIntervalSince(lastShownAt) < cooldown {
            completion?(); return
        }

        // 沒有可用廣告 → 先預載，直接往下做原動作
        guard let ad = ad else {
            preload()
            completion?()
            return
        }

        lastShownAt = Date()
        self.ad = nil // 一次性
        if isDebugMode {
            print("🛠 [DEBUG] Showing Test Ad")
        } else {
            print("📢 Showing Real Ad")
        }
        ad.present(from: viewController)
        // 在關閉時觸發 completion（見 delegate）
        self.pendingCompletion = completion
    }

    // 在 onAppear 這種時機使用：有就顯示，沒有就算了
    func maybeShow(from vc: UIViewController) {
        showIfReady(from: vc, completion: nil)
    }

    // MARK: - FullScreenContentDelegate
    private var pendingCompletion: (() -> Void)?
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        // 關閉後自動再載下一支
        preload()
        // 執行原本動作
        pendingCompletion?()
        pendingCompletion = nil
    }
}

// MARK: - 便捷：取得最上層 VC
extension UIApplication {
    func topViewController(base: UIViewController? = {
        // iOS 13+：抓最前景 Scene 的 keyWindow
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
        return scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
    }()) -> UIViewController? {
        if let nav = base as? UINavigationController { return topViewController(base: nav.visibleViewController) }
        if let tab = base as? UITabBarController { return topViewController(base: tab.selectedViewController) }
        if let presented = base?.presentedViewController { return topViewController(base: presented) }
        return base
    }
}
