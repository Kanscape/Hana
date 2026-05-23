import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension View {
    @ViewBuilder
    func hanaSearchInput(text: Binding<String>, isEnabled: Bool) -> some View {
        if isEnabled {
            searchable(text: text, prompt: "关键词")
                .searchPresentationToolbarBehavior(.avoidHidingContent)
        } else {
            self
        }
    }

    @ViewBuilder
    func hanaNavigationSubtitle(_ subtitle: String?) -> some View {
        if let subtitle {
            navigationSubtitle(subtitle)
        } else {
            self
        }
    }

    @ViewBuilder
    func hanaSystemBackground() -> some View {
#if canImport(UIKit)
        background(Color(uiColor: .systemBackground))
#elseif canImport(AppKit)
        background(Color(nsColor: .windowBackgroundColor))
#else
        background(Color.clear)
#endif
    }

    @ViewBuilder
    func hanaMobileNavigationChrome() -> some View {
#if os(iOS)
        navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarBackground(.visible, for: .tabBar)
#else
        self
#endif
    }

    @ViewBuilder
    func hanaInlineNavigationTitleDisplayMode() -> some View {
#if os(iOS)
        navigationBarTitleDisplayMode(.inline)
#else
        self
#endif
    }

    @ViewBuilder
    func hanaPreviewImagePagerStyle(showIndex: Bool) -> some View {
#if os(iOS)
        tabViewStyle(.page(indexDisplayMode: showIndex ? .automatic : .never))
#else
        self
#endif
    }

    @ViewBuilder
    func hanaEmailKeyboard() -> some View {
#if canImport(UIKit)
        keyboardType(.emailAddress)
#else
        self
#endif
    }

    @ViewBuilder
    func hanaURLKeyboard() -> some View {
#if canImport(UIKit)
        keyboardType(.URL)
#else
        self
#endif
    }

    @ViewBuilder
    func hanaTextInputAutocapitalizationNever() -> some View {
#if canImport(UIKit)
        textInputAutocapitalization(.never)
#else
        self
#endif
    }

    @ViewBuilder
    func hanaNumberKeyboard() -> some View {
#if canImport(UIKit)
        keyboardType(.numberPad)
#else
        self
#endif
    }
}

enum HanaPasteboard {
    static var string: String? {
        get {
#if canImport(UIKit)
            UIPasteboard.general.string
#elseif canImport(AppKit)
            NSPasteboard.general.string(forType: .string)
#else
            nil
#endif
        }
        set {
#if canImport(UIKit)
            UIPasteboard.general.string = newValue
#elseif canImport(AppKit)
            NSPasteboard.general.clearContents()
            if let newValue {
                NSPasteboard.general.setString(newValue, forType: .string)
            }
#endif
        }
    }
}
