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
    @State private var expandedFolderIDs: Set<UUID>

    init(
        folders: [LibraryFolderNode],
        excluding: Set<UUID> = [],
        selectedFolderID: UUID? = nil,
        includesLibraryRoot: Bool = false,
        onSelect: @escaping (UUID?) -> Void
    ) {
        self.folders = folders
        self.excluding = excluding
        self.selectedFolderID = selectedFolderID
        self.includesLibraryRoot = includesLibraryRoot
        self.onSelect = onSelect
        _expandedFolderIDs = State(
            initialValue: LibraryFolderOutline.initiallyExpandedFolderIDs(
                in: folders,
                selectedFolderID: selectedFolderID
            )
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DesignMetrics.space4) {
                if includesLibraryRoot {
                    rootButton
                }

                ForEach(visibleRows) { row in
                    LibraryFolderTreePickerRow(
                        row: row,
                        isExpanded: expandedFolderIDs.contains(row.id),
                        selectedFolderID: selectedFolderID,
                        onToggleExpansion: { toggleExpansion(row.id) },
                        onSelect: onSelect
                    )
                }
            }
            .padding(DesignMetrics.space8)
        }
        .background(palette.surfaceElevated, in: .rect(cornerRadius: DesignMetrics.cornerRadius))
        .accessibilityLabel("选择文件夹")
        .onChange(of: selectedFolderID) { _, selectedFolderID in
            expandPath(to: selectedFolderID)
        }
        .onChange(of: allFolderIDs) { _, currentFolderIDs in
            expandedFolderIDs.formIntersection(currentFolderIDs)
            expandPath(to: selectedFolderID)
        }
    }

    private var visibleRows: [LibraryFolderOutlineRow] {
        LibraryFolderOutline.visibleRows(
            in: folders,
            expandedFolderIDs: expandedFolderIDs,
            excluding: excluding
        )
    }

    private var allFolderIDs: Set<UUID> {
        LibraryFolderOutline.allFolderIDs(in: folders)
    }

    private func toggleExpansion(_ folderID: UUID) {
        if expandedFolderIDs.contains(folderID) {
            expandedFolderIDs.remove(folderID)
        } else {
            expandedFolderIDs.insert(folderID)
        }
    }

    private func expandPath(to folderID: UUID?) {
        expandedFolderIDs.formUnion(
            LibraryFolderOutline.initiallyExpandedFolderIDs(
                in: folders,
                selectedFolderID: folderID
            )
        )
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

private struct LibraryFolderTreePickerRow: View {
    let row: LibraryFolderOutlineRow
    let isExpanded: Bool
    let selectedFolderID: UUID?
    let onToggleExpansion: () -> Void
    let onSelect: (UUID?) -> Void

    @Environment(\.designPalette) private var palette

    var body: some View {
        HStack(spacing: DesignMetrics.space4) {
            if row.hasChildren {
                Button(
                    isExpanded ? "收起\(row.folder.name)" : "展开\(row.folder.name)",
                    systemImage: "chevron.right",
                    action: onToggleExpansion
                )
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(palette.textSecondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: DesignMetrics.space16, height: DesignMetrics.space24)
            } else {
                Color.clear
                    .frame(width: DesignMetrics.space16, height: DesignMetrics.space24)
                    .accessibilityHidden(true)
            }

            folderButton
        }
        .padding(.leading, CGFloat(row.depth) * DesignMetrics.space16)
    }

    private var folderButton: some View {
        Button {
            onSelect(row.folder.id)
        } label: {
            HStack(spacing: DesignMetrics.space8) {
                Image(systemName: selectedFolderID == row.folder.id ? "checkmark" : "folder")
                    .frame(width: DesignMetrics.space16)
                    .accessibilityHidden(true)
                Text(row.folder.name)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(DesignTypography.body)
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, DesignMetrics.space8)
            .frame(minHeight: DesignMetrics.titlebarControlSize, alignment: .leading)
            .background(
                selectedFolderID == row.folder.id ? palette.selection : Color.clear,
                in: .rect(cornerRadius: DesignMetrics.space4)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.folder.name)
        .accessibilityIdentifier("library.folder.\(row.folder.id.uuidString)")
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
