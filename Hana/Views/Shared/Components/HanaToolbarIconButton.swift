import SwiftUI

struct HanaToolbarIconButton: View {
    let title: String
    let systemImage: String
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
        }
        .accessibilityLabel(title)
    }
}
