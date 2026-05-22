import SwiftUI

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
}
