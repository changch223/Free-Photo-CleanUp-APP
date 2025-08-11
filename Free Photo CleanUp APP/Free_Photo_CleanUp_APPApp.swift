import SwiftUI
import SwiftData
import UIKit
import GoogleMobileAds

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {

        // 確認 Info.plist 有讀到 App ID（除錯用）
        let appID = Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String ?? "nil"
        print("GADApplicationIdentifier =", appID)

        // ✅ 正確初始化 AdMob SDK（v10/v11 皆可用）
        MobileAds.shared.start(completionHandler: nil)
        InterstitialAdManager.shared.preload()

        return true
    }
}

@main
struct Free_Photo_CleanUp_APPApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Item.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // 等畫面起來後再載 App Open Ad，避免與 SDK 初始化衝突
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        AppOpenAdManager.shared.loadAd()
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
