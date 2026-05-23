//
//  HanaApp.swift
//  Hana
//
//  Created by Kanscape on 2026/5/16.
//

import SwiftUI
import SwiftData
#if canImport(UIKit) && os(iOS)
import UIKit
#endif
import UserNotifications

#if canImport(UIKit) && os(iOS)
final class HanaAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        HanaInterfaceOrientationController.supportedInterfaceOrientations
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        HanimeDownloadClient.handleBackgroundEvents(
            identifier: identifier,
            completionHandler: completionHandler
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
#endif

@main
struct HanaApp: App {
#if canImport(UIKit) && os(iOS)
    @UIApplicationDelegateAdaptor(HanaAppDelegate.self) private var appDelegate
#endif
    @State private var services = HanaServices()
    @State private var servicesIdentity = UUID()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            WatchHistoryRecord.self,
            SearchHistoryRecord.self,
            AdvancedSearchHistoryRecord.self,
            FavoriteVideoRecord.self,
            WatchLaterRecord.self,
            PlaylistRecord.self,
            PlaylistItemRecord.self,
            DownloadQueueRecord.self,
            DownloadGroupRecord.self,
            HKeyframeRecord.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .id(servicesIdentity)
                .environment(services)
                .environment(\.hanaReloadServices, reloadServicesAction)
        }
        .modelContainer(sharedModelContainer)

#if os(macOS)
        Settings {
            SettingsScreen()
                .environment(services)
                .environment(\.hanaReloadServices, reloadServicesAction)
        }
        .modelContainer(sharedModelContainer)
#endif
    }

    private var reloadServicesAction: HanaServiceReloadAction {
        HanaServiceReloadAction { baseURL in
            services.siteSession.cancel()
            services = HanaServices(baseURL: baseURL)
            servicesIdentity = UUID()
        }
    }
}
