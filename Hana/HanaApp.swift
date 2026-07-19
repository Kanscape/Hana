//
//  HanaApp.swift
//  Hana
//
//  Created by Kanscape on 2026/5/16.
//

import SwiftUI
import SwiftData
#if canImport(AppKit) && os(macOS)
import AppKit
#endif
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
    @State private var disciplineModeStore = DisciplineModeStore()
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
                .environment(disciplineModeStore)
                .environment(\.hanaReloadServices, reloadServicesAction)
        }
        .modelContainer(sharedModelContainer)
#if os(macOS)
        .defaultSize(width: 1300, height: 720)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置...") {
                    HanaSettingsWindowController.shared.open(
                        services: services,
                        disciplineModeStore: disciplineModeStore,
                        reloadServicesAction: reloadServicesAction,
                        modelContainer: sharedModelContainer
                    )
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
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

#if os(macOS)
@MainActor
private final class HanaSettingsWindowController {
    static let shared = HanaSettingsWindowController()

    private var window: NSWindow?

    private init() {}

    func open(
        services: HanaServices,
        disciplineModeStore: DisciplineModeStore,
        reloadServicesAction: HanaServiceReloadAction,
        modelContainer: ModelContainer
    ) {
        let rootView = makeRootView(
            services: services,
            disciplineModeStore: disciplineModeStore,
            reloadServicesAction: reloadServicesAction,
            modelContainer: modelContainer
        )

        if let window {
            if let hostingController = window.contentViewController as? NSHostingController<AnyView> {
                hostingController.rootView = rootView
            }
            show(window)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 800, height: 600)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "设置"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        window.minSize = NSSize(width: 680, height: 600)
        window.contentViewController = NSHostingController(rootView: rootView)
        window.center()

        self.window = window
        show(window)
    }

    private func show(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeRootView(
        services: HanaServices,
        disciplineModeStore: DisciplineModeStore,
        reloadServicesAction: HanaServiceReloadAction,
        modelContainer: ModelContainer
    ) -> AnyView {
        AnyView(
            SettingsScreen()
                .environment(services)
                .environment(disciplineModeStore)
                .environment(\.hanaReloadServices, reloadServicesAction)
                .modelContainer(modelContainer)
                .frame(minWidth: 680, minHeight: 600)
                .ignoresSafeArea()
        )
    }
}
#endif
