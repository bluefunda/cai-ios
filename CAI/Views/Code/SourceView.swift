import SwiftUI

// MARK: - Source View (read-only ABAP source with syntax highlighting)

struct SourceView: View {
    let api: CodeAPIService
    let ref: ObjectRef

    @Environment(\.colorScheme) private var colorScheme
    @State private var source: String?
    @State private var loading = true
    @State private var error: String?
    @State private var didCopy = false

    var body: some View {
        Group {
            if loading {
                ProgressView("Loading source…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                ContentUnavailableView(
                    "Couldn't load source",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if let source {
                ScrollView([.vertical, .horizontal]) {
                    Text(ABAPHighlighter.highlight(source, isDark: colorScheme == .dark))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle(ref.objectName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if source != nil {
                    Button {
                        copy()
                    } label: {
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    }
                }
            }
        }
        .task(id: ref) { await load() }
    }

    private func load() async {
        loading = true
        error = nil
        do {
            let result = try await api.getObject(
                type: ref.objectType,
                name: ref.objectName,
                functionGroup: ref.functionGroup
            )
            source = result.source
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func copy() {
        UIPasteboard.general.string = source
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            didCopy = false
        }
    }
}
