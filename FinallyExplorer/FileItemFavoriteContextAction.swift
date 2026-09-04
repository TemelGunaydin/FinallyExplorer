//
//  FileItemFavoriteContextAction.swift
//  FinallyExplorer
//

import SwiftUI

struct FileItemFavoriteContextAction: View {
    let item: FileItem
    let sidebar: SidebarModel
    let onDismiss: () -> Void

    var body: some View {
        if let favorite = sidebar.favorite(for: item.url) {
            ExplorerContextMenuActionButton(
                title: "Remove from Favorites",
                systemImage: "star.slash"
            ) {
                onDismiss()
                sidebar.remove(favorite)
            }
        } else if sidebar.canAdd(
            itemURL: item.url,
            isDirectory: item.isDirectory
        ) {
            ExplorerContextMenuActionButton(
                title: "Add to Favorites",
                systemImage: "star"
            ) {
                onDismiss()
                sidebar.add(
                    itemURL: item.url,
                    isDirectory: item.isDirectory
                )
            }
        }
    }
}
