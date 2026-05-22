import SwiftUI

struct HanaToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let style: Style

    enum Style: Equatable {
        case success
        case info

        var systemImage: String {
            switch self {
            case .success:
                "checkmark.circle.fill"
            case .info:
                "info.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .success:
                .green
            case .info:
                .blue
            }
        }
    }

    static func success(_ text: String) -> HanaToastMessage {
        HanaToastMessage(text: text, style: .success)
    }

    static func info(_ text: String) -> HanaToastMessage {
        HanaToastMessage(text: text, style: .info)
    }
}

struct HanaAlertMessage: Identifiable {
    let id = UUID()
    let title: String
    let message: String

    static func error(_ message: String) -> HanaAlertMessage {
        HanaAlertMessage(title: "操作失败", message: message)
    }
}

enum HanaToastContentSize {
    case regular
    case compact

    var spacing: CGFloat {
        switch self {
        case .regular:
            10
        case .compact:
            7
        }
    }

    var iconFont: Font {
        switch self {
        case .regular:
            .body
        case .compact:
            .caption.weight(.semibold)
        }
    }

    var textFont: Font {
        switch self {
        case .regular:
            .subheadline.weight(.semibold)
        case .compact:
            .caption.weight(.semibold)
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .regular:
            14
        case .compact:
            11
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .regular:
            10
        case .compact:
            7
        }
    }

    var shadowRadius: CGFloat {
        switch self {
        case .regular:
            14
        case .compact:
            10
        }
    }

    var shadowY: CGFloat {
        switch self {
        case .regular:
            8
        case .compact:
            5
        }
    }
}

extension View {
    func hanaToast(_ toast: Binding<HanaToastMessage?>) -> some View {
        modifier(HanaToastModifier(toast: toast))
    }

    func hanaFeedbackAlert(_ alert: Binding<HanaAlertMessage?>) -> some View {
        self.alert(item: alert) { message in
            Alert(
                title: Text(message.title),
                message: Text(message.message),
                dismissButton: .default(Text("好"))
            )
        }
    }
}

private struct HanaToastModifier: ViewModifier {
    @Binding var toast: HanaToastMessage?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast {
                    HanaToastContentView(message: toast)
                        .padding(.top, 10)
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .animation(.snappy(duration: 0.24), value: toast?.id)
            .sensoryFeedback(.success, trigger: toast?.id)
            .onChange(of: toast?.id) { _, newValue in
                guard let newValue else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    if toast?.id == newValue {
                        toast = nil
                    }
                }
            }
    }
}

struct HanaToastContentView: View {
    let text: String
    let style: HanaToastMessage.Style
    let systemImage: String?
    let size: HanaToastContentSize

    init(message: HanaToastMessage) {
        self.text = message.text
        self.style = message.style
        self.systemImage = nil
        self.size = .regular
    }

    init(
        _ text: String,
        style: HanaToastMessage.Style = .info,
        systemImage: String? = nil,
        size: HanaToastContentSize = .regular
    ) {
        self.text = text
        self.style = style
        self.systemImage = systemImage
        self.size = size
    }

    var body: some View {
        HStack(spacing: size.spacing) {
            Image(systemName: systemImage ?? style.systemImage)
                .font(size.iconFont)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, style.tint)

            Text(text)
                .font(size.textFont)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(.white.opacity(0.16))
        )
        .shadow(color: .black.opacity(0.24), radius: size.shadowRadius, y: size.shadowY)
    }
}
