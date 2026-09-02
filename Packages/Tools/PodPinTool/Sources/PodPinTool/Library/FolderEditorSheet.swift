import OneBoxDesignSystem
import SwiftUI

/// A single editor request shared by the sidebar, folder actions, and import
/// workspace. Keeping its source and defaults together makes every entry point
/// express the same folder semantics.
struct FolderEditorRequest: Identifiable {
    enum Operation {
        case create
        case rename(folderID: UUID)
    }

    enum Source {
        case sidebar
        case folderMenu
        case importWorkspace
    }

    let id: UUID
    let operation: Operation
    let source: Source
    let initialName: String
    let defaultParentID: UUID?
    let onSaved: (LibraryFolder) -> Void

    init(
        operation: Operation,
        source: Source,
        initialName: String = "",
        defaultParentID: UUID? = nil,
        onSaved: @escaping (LibraryFolder) -> Void = { _ in }
    ) {
        self.id = UUID()
        self.operation = operation
        self.source = source
        self.initialName = initialName
        self.defaultParentID = defaultParentID
        self.onSaved = onSaved
    }

    var title: String {
        switch operation {
        case .create: "新建文件夹"
        case .rename: "重命名文件夹"
        }
    }

    var createsFolder: Bool {
        if case .create = operation { return true }
        return false
    }
}

/// A focused native sheet rather than an inline draft: the name, parent
/// location, confirmation, and cancellation are all visible at once.
struct FolderEditorSheet: View {
    typealias SaveCompletion = @MainActor @Sendable (String?) -> Void

    let request: FolderEditorRequest
    let folderTree: [LibraryFolderNode]
    let onSave: (String, UUID?, @escaping SaveCompletion) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFocused: Bool
    @Environment(\.designPalette) private var palette
    @State private var name: String
    @State private var parentID: UUID?
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(
        request: FolderEditorRequest,
        folderTree: [LibraryFolderNode],
        onSave: @escaping (String, UUID?, @escaping SaveCompletion) -> Void
    ) {
        self.request = request
        self.folderTree = folderTree
        self.onSave = onSave
        _name = State(initialValue: request.initialName)
        _parentID = State(initialValue: request.defaultParentID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.space16) {
            Text(request.title)
                .font(DesignTypography.sectionTitle)

            TextField("文件夹名称", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)
                .disabled(isSaving)
                .onSubmit(save)
                .accessibilityIdentifier("library.folder-editor.name")

            if request.createsFolder {
                Text("位置")
                    .font(DesignTypography.bodyMedium)

                LibraryFolderTreePicker(
                    folders: folderTree,
                    selectedFolderID: parentID,
                    includesLibraryRoot: true,
                    onSelect: { parentID = $0 }
                )
                .frame(minHeight: 140, maxHeight: 240)
                .accessibilityIdentifier("library.folder-editor.parent")
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(DesignTypography.metadata)
                    .foregroundStyle(palette.negative)
                    .accessibilityIdentifier("library.folder-editor.error")
            }

            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSaving)
                Spacer()
                Button(request.createsFolder ? "创建" : "保存", action: save)
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    .accessibilityIdentifier("library.folder-editor.save")
            }
        }
        .padding(DesignMetrics.space24)
        .frame(width: 420)
        .task { isNameFocused = true }
    }

    private func save() {
        guard !isSaving else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "请输入文件夹名称。"
            return
        }
        isSaving = true
        errorMessage = nil
        onSave(trimmedName, parentID) { failure in
            isSaving = false
            if let failure {
                errorMessage = failure
                isNameFocused = true
            } else {
                dismiss()
            }
        }
    }
}
