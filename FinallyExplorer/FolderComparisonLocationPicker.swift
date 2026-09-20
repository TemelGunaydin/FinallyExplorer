import SwiftUI

/// A real full-width button: native macOS Menu labels discard custom surfaces.
struct FolderComparisonLocationPicker: View {
    let title: String
    let locations: [FolderComparisonLocation]
    @Binding var selection: UUID?
    @State private var isPresented = false

    private var selectedTitle: String {
        locations.first { $0.id == selection }?.title ?? "Choose a panel"
    }

    var body: some View {
        Button { isPresented = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                Text(selectedTitle).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(ExplorerDialogButtonStyle())
        .disabled(locations.isEmpty)
        .accessibilityLabel("\(title) folder")
        .accessibilityValue(selectedTitle)
        .accessibilityIdentifier("folder-comparison-\(title.lowercased())")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            FolderComparisonLocationOptions(locations: locations, selection: selection) { id in
                selection = id
                isPresented = false
            }
            .onExitCommand { isPresented = false }
        }
    }
}

struct FolderComparisonLocationOptions: View {
    @Environment(\.explorerTheme) private var theme
    @FocusState private var focusedID: UUID?
    let locations: [FolderComparisonLocation]
    let selection: UUID?
    let onSelect: (UUID) -> Void

    var body: some View {
        VStack(spacing: 6) {
            ForEach(locations) { location in
                Button { onSelect(location.id) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "folder").foregroundStyle(theme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(location.title).font(.callout.weight(.semibold))
                                .foregroundStyle(theme.textPrimary).lineLimit(1)
                            Text(location.url.path).font(.caption)
                                .foregroundStyle(theme.textSecondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer(minLength: 0)
                        if location.id == selection {
                            Image(systemName: "checkmark").foregroundStyle(theme.accent)
                        }
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(location.id == selection ? theme.selectedRow : theme.control, in: .rect(cornerRadius: 8))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .focused($focusedID, equals: location.id)
                .accessibilityLabel(location.title)
                .accessibilityValue(location.id == selection ? "Selected" : "")
                .accessibilityAddTraits(location.id == selection ? .isSelected : [])
                .accessibilityIdentifier("folder-comparison-option-\(location.id)")
            }
        }
        .padding(10).frame(width: 340)
        .background(theme.elevatedPanel)
        .defaultFocus($focusedID, selection ?? locations.first?.id)
    }
}
