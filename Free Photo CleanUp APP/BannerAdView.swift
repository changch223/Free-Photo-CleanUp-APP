//
//  BannerAdView.swift
//  Free Photo CleanUp APP
//
//  Created by chang chiawei on 2025-08-10.
//

// BannerAdView.swift
import SwiftUI
import GoogleMobileAds

struct BannerAdView: UIViewRepresentable {
    /// 你的廣告單元 ID；Debug 會自動替換成測試 ID
    var adUnitID: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView()
        banner.delegate = context.coordinator
        banner.adUnitID = currentAdUnitID()
        banner.rootViewController = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first?.rootViewController
        banner.translatesAutoresizingMaskIntoConstraints = false

        // 先給一個預設尺寸，等會在 updateUIView 依寬度調整
        banner.adSize = AdSizeBanner
        banner.load(Request())
        return banner
    }

    func updateUIView(_ banner: BannerView, context: Context) {
        // 用螢幕/容器寬度計算自適應尺寸
        let viewWidth = banner.bounds.width > 0 ? banner.bounds.width : UIScreen.main.bounds.width
        let size = portraitAnchoredAdaptiveBanner(width: viewWidth)
        if !isAdSizeEqualToSize(size1: banner.adSize, size2: size) {
            banner.adSize = size
            banner.load(Request())
        }
    }

    // Debug 時自動用測試 ID，避免送審前被封鎖
    private func currentAdUnitID() -> String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/2934735716" // 官方測試 Banner
        #else
        return adUnitID
        #endif
    }

    final class Coordinator: NSObject, BannerViewDelegate {
        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            print("✅ Banner loaded")
        }
        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            print("❌ Banner failed:", error.localizedDescription)
        }
    }
}
