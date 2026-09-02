import OneBoxDesignSystem
import SwiftUI

/// One surface for folder selection. It replaces cascading menus everywhere a
/// user chooses a library location, while preserving the existing tree model.
struct LibraryFolderTreePicker: View {
    let folders: [LibraryFolderNode]
    var excluding: Set<UUID> = []
    var selectedFolderID: UUID?
    var includesLibraryRoot = false
    let onSelect: (UUID?) -> Void

    @Environment(\.designPalette) private var palette

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DesignMetrics.space4) {
                if includesLibraryRoot {
                    rootButton
                }

                ForEach(folders) { folder in
                    LibraryFolderTreePickerNode(
                        folder: folder,
                        excluding: excluding,
                        selectedFolderID: selectedFolderID,
                        onSelect: onSelect
                    )
                }
            }
            .padding(DesignMetrics.space8)
        }
        .background(palette.surfaceElevated, in: .rect(cornerRadius: DesignMetrics.cornerRadius))
        .accessibilityLabel("选择文件夹")
    }

    private var rootButton: some View {
        Button {
            onSelect(nil)
        } label: {
            pickerLabel("资料库根目录", isSelected: selectedFolderID == nil)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("资料库根目录")
    }

    private func pickerLabel(_ title: String, isSelected: Bool) -> some View {
        HStack(spacing: DesignMetrics.space8) {
            Image(systemName: isSelected ? "checkmark" : "folder")
                .frame(width: DesignMetrics.space16)
                .accessibilityHidden(true)
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(DesignTypography.body)
        .foregroundStyle(palette.textPrimary)
        .padding(.horizontal, DesignMetrics.space8)
        .frame(minHeight: DesignMetrics.titlebarControlSize, alignment: .leading)
        .background(
            isSelected ? palette.selection : Color.clear,
            in: .rect(cornerRadius: DesignMetrics.space4)
        )
    }
}

private struct LibraryFolderTreePickerNode: View {
    let folder: LibraryFolderNode
    let excluding: Set<UUID>
    let selectedFolderID: UUID?
    let onSelect: (UUID?) -> Void

    @Environment(\.designPalette) private var palette
    @State private var isExpanded = true

    var body: some View {
        if excluding.contains(folder.id) {
            ForEach(folder.children) { child in
                LibraryFolderTreePickerNode(
                    folder: child,
                    excluding: excluding,
                    selectedFolderID: selectedFolderID,
                    onSelect: onSelect
                )
            }
        } else if folder.children.isEmpty {
            folderButton
        } else {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: DesignMetrics.space4) {
                    ForEach(folder.children) { child in
                        LibraryFolderTreePickerNode(
                            folder: child,
                            excluding: excluding,
                            selectedFolderID: selectedFolderID,
                            onSelect: onSelect
                        )
                    }
                }
                .padding(.leading, DesignMetrics.space16)
            } label: {
                folderButton
            }
            .tint(palette.textSecondary)
        }
    }

    private var folderButton: some View {
        Button {
            onSelect(folder.id)
        } label: {
            HStack(spacing: DesignMetrics.space8) {
                Image(systemName: selectedFolderID == folder.id ? "checkmark" : "folder")
                    .frame(width: DesignMetrics.space16)
                    .accessibilityHidden(true)
                Text(folder.name)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(DesignTypography.body)
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, DesignMetrics.space8)
            .frame(minHeight: DesignMetrics.titlebarControlSize, alignment: .leading)
            .background(
                selectedFolderID == folder.id ? palette.selection : Color.clear,
                in: .rect(cornerRadius: DesignMetrics.space4)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(folder.name)
        .accessibilityIdentifier("library.folder.\(folder.id.uuidString)")
    }
}

struct LibraryCollectionPickerPanel: View {
    let folders: [LibraryFolderNode]
    let selectedCollection: LibraryCollection
    let onSelect: (LibraryCollection) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.designPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.space8) {
            Text("资料集合")
                .font(DesignTypography.sectionTitle)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, DesignMetrics.space8)

            collectionButton("最近导入", collection: .recentlyImported)
            collectionButton("最近播放", collection: .recentlyPlayed)
            collectionButton("已下载", collection: .downloaded)

            Divider()
                .padding(.vertical, DesignMetrics.space4)

            Text("文件夹")
                .font(DesignTypography.sectionTitle)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, DesignMetrics.space8)

            LibraryFolderTreePicker(
                folders: folders,
                selectedFolderID: selectedFolderID
            ) { folderID in
                guard let folderID else { return }
                select(.folder(folderID))
            }
            .frame(maxHeight: 300)
        }
        .padding(DesignMetrics.space8)
        .frame(width: 300, alignment: .leading)
        .accessibilityLabel("资料集合和文件夹")
    }

    private var selectedFolderID: UUID? {
        guard case .folder(let folderID) = selectedCollection else { return nil }
        return folderID
    }

    private func collectionButton(_ title: String, collection: LibraryCollection) -> some View {
        Button {
            select(collection)
        } label: {
            HStack(spacing: DesignMetrics.space8) {
                Image(systemName: selectedCollection == collection ? "checkmark" : "clock")
                    .frame(width: DesignMetrics.space16)
                    .accessibilityHidden(true)
                Text(title)
                Spacer(minLength: 0)
            }
            .font(DesignTypography.body)
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, DesignMetrics.space8)
            .frame(minHeight: DesignMetrics.titlebarControlSize, alignment: .leading)
            .background(
                selectedCollection == collection ? palette.selection : Color.clear,
                in: .rect(cornerRadius: DesignMetrics.space4)
            )
        }
        .buttonStyle(.plain)
    }

    private func select(_ collection: LibraryCollection) {
        onSelect(collection)
        dismiss()
    }
}
