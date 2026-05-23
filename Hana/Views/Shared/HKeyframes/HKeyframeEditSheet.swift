import SwiftUI

struct HKeyframeEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let onSave: (HKeyframeEntry) -> Void
    @State private var positionMilliseconds: Int64
    @State private var promptText: String

    init(
        title: String,
        initialPositionMilliseconds: Int64,
        initialPrompt: String = "",
        onSave: @escaping (HKeyframeEntry) -> Void
    ) {
        self.title = title
        self.onSave = onSave
        _positionMilliseconds = State(initialValue: initialPositionMilliseconds)
        _promptText = State(initialValue: initialPrompt)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("时间") {
                    LabeledContent("时间", value: formatTime(TimeInterval(positionMilliseconds) / 1_000))
                    TextField("位置（毫秒）", value: $positionMilliseconds, format: .number)
                        .hanaNumberKeyboard()
                    HStack {
                        Button("-5 秒") { adjust(by: -5_000) }
                        Button("-1 秒") { adjust(by: -1_000) }
                        Button("+1 秒") { adjust(by: 1_000) }
                        Button("+5 秒") { adjust(by: 5_000) }
                    }
                    .buttonStyle(.bordered)
                }

                Section("提示") {
                    TextField("提示，可留空", text: $promptText)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    HanaToolbarIconButton(title: "取消", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    HanaToolbarIconButton(title: "保存", systemImage: "checkmark") {
                        onSave(HKeyframeEntry(
                            positionMilliseconds: max(positionMilliseconds, 0),
                            prompt: promptText
                        ))
                        dismiss()
                    }
                    .disabled(positionMilliseconds < 0)
                }
            }
        }
    }

    private func adjust(by value: Int64) {
        positionMilliseconds = max(positionMilliseconds + value, 0)
    }
}
