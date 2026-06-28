import AVKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct HomeScreen: View {
    @Environment(HanaServices.self) private var services
    @State private var state: LoadableState<HanimeHomePage> = .idle
    @State private var isDisciplineModePresented = false

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                ProgressView("加载首页")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let homePage):
                if homePage.sections.isEmpty {
                    ContentUnavailableView("首页暂无内容", systemImage: "film")
                } else if let banner = homePage.banner {
                    HomeHeroContentTransition(
                        banner: banner,
                        sections: homePage.sections
                    )
                } else {
                    ScrollView {
                        HomeSectionsView(sections: homePage.sections)
                            .padding(.top, 16)
                        .padding(.bottom)
                    }
                    .hanaHomeTopScrollEdgeSoft()
                    .hanaSystemBackground()
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label(message, systemImage: "exclamationmark.triangle")
                } actions: {
                    Button("重试") {
                        Task { await loadHome() }
                    }
                }
            }
        }
        .navigationTitle("Hana")
        .hanaMobileNavigationChrome()
        .disciplineModeToolbar(isPresented: $isDisciplineModePresented)
        .sheet(isPresented: $isDisciplineModePresented) {
            DisciplineModeSetupSheet()
        }
        .task {
            if case .idle = state {
                await loadHome()
            }
        }
        .onChange(of: services.siteSession.lastCookieSyncAt) {
            Task { await loadHome() }
        }
    }

    private func loadHome() async {
        state = .loading
        do {
            state = .loaded(try await services.repository.homePage())
        } catch {
            if services.siteSession.handle(error) {
                state = .failed("需要 Cloudflare 验证")
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func disciplineModeToolbar(isPresented: Binding<Bool>) -> some View {
#if os(macOS)
        self
#else
        toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    isPresented.wrappedValue = true
                } label: {
                    Label("自律模式", systemImage: "calendar.badge.lock")
                }
            }
        }
#endif
    }
}
