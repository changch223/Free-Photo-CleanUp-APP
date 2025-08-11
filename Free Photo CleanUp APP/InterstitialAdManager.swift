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
    func showIfReady(from viewController: UIViewController?, completion: (() -> Void)? = nil) {
        // 冷卻
        if Date().timeIntervalSince(lastShownAt) < cooldown {
            completion?(); return
        }

        // 先確認 VC 在 window 階層
        guard let vc = viewController, vc.viewIfLoaded?.window != nil else {
            // 若還在過場，0.6 秒後試一次
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self = self else { return }
                let retryVC = UIApplication.shared.topMostVisibleViewController()
                self.showIfReady(from: retryVC, completion: completion)
            }
            return
        }

        guard let ad = ad else {
            preload()
            completion?()
            return
        }

        lastShownAt = Date()
        self.ad = nil
        pendingCompletion = completion
        ad.present(from: vc)
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
    /// 取得目前前景 Scene 的 keyWindow
    func keyWindow() -> UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows
            .first { $0.isKeyWindow }
    }

    /// 找到最上層、而且確定「在 window 階層中的」VC
    func topMostVisibleViewController() -> UIViewController? {
        guard var vc = keyWindow()?.rootViewController else { return nil }

        func visible(from base: UIViewController) -> UIViewController {
            if let nav = base as? UINavigationController, let top = nav.visibleViewController {
                return visible(from: top)
            }
            if let tab = base as? UITabBarController, let sel = tab.selectedViewController {
                return visible(from: sel)
            }
            if let presented = base.presentedViewController {
                return visible(from: presented)
            }
            return base
        }

        vc = visible(from: vc)

        // 若目前這個 VC 不在 window 階層，往它的 presentingViewController 回退，直到找到在 window 的
        var safe = vc
        while safe.viewIfLoaded?.window == nil, let presenter = safe.presentingViewController {
            safe = presenter
        }
        return (safe.viewIfLoaded?.window != nil) ? safe : keyWindow()?.rootViewController
    }
}

