import SwiftUI

struct HanaInfiniteScrollTrigger: View {
    let isActive: Bool
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Group {
            if isActive {
                HStack {
                    if isLoading {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: isLoading ? 44 : 1)
                .padding(.vertical, isLoading ? 8 : 0)
                .onAppear {
                    guard !isLoading else { return }
                    action()
                }
                .accessibilityHidden(!isLoading)
            }
        }
    }
}

enum HanaInfiniteScrollPreload {
    static let threshold = 6

    static func shouldLoadNextPage<ID: Hashable>(currentID: ID, orderedIDs: [ID]) -> Bool {
        guard !orderedIDs.isEmpty else { return false }
        return orderedIDs.suffix(threshold).contains(currentID)
    }
}
