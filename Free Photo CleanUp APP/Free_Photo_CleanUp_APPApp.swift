import SwiftUI
import SwiftData
import GoogleMobileAds
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        MobileAds.shared.start(completionHandler: nil)
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        AppOpenAdManager.shared.loadAd()
                    }
                }
        }
        // 這個修飾子要掛在 WindowGroup（Scene）外面
        .modelContainer(sharedModelContainer)
    }
}
