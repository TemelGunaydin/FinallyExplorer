import SwiftUI

struct DuplicateGroupView: View {
    @Environment(\.explorerTheme) private var theme
    let group: DuplicateGroup
    let selection: Set<String>
    let onToggle: (ComparedFolderEntry) -> Void
    let onReveal: (ComparedFolderEntry) -> Void

    var body: some View {
        let selectedCount = group.files.count { selection.contains($0.relativePath) }
        LazyVStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("\(group.files.count) identical files", systemImage: "doc.on.doc")
                    .font(.headline)
                Spacer()
                Text("\(group.fileSize.formatted(.byteCount(style: .file))) each")
                    .font(.callout).foregroundStyle(theme.textSecondary)
            }
            Text("\(group.files.count - selectedCount) kept · Select copies to move to Trash")
                .font(.caption).foregroundStyle(theme.textSecondary)
            ForEach(group.files, id: \.relativePath) { file in
                HStack(spacing: 12) {
                    let isSelected = selection.contains(file.relativePath)
                    Button {
                        onToggle(file)
                    } label: {
                        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                            .font(.title3)
                            .foregroundStyle(isSelected ? theme.accent : theme.textSecondary)
                            .frame(width: 28, height: 32)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSelected == false && selectedCount == group.files.count - 1)
                    .accessibilityLabel("Select \(file.relativePath) for Trash")
                    .accessibilityValue(isSelected ? "Selected" : "Not selected")
                    .accessibilityIdentifier("duplicate-select-\(file.relativePath)")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(file.relativePath)
                            .font(.callout.weight(.medium))
                            .lineLimit(2).truncationMode(.middle)
                            .help(file.relativePath)
                        Text("Modified \(Date(timeIntervalSince1970: Double(file.state.modifiedSeconds)).formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Show in Panel", systemImage: "arrow.up.forward.square") { onReveal(file) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .help("Show \(file.relativePath) in the file panel")
                }
                .padding(8)
                .background(theme.row.opacity(selection.contains(file.relativePath) ? 1 : 0), in: .rect(cornerRadius: 8))
            }
        }
        .padding(14)
        .background(theme.control, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }
}
