import SwiftUI

struct AppContextMenu: View {
    @Bindable var appModel: AppModel
    let app: Application
    @Binding var selectedAppPathsForFolder: [String]
    @Binding var newFolderName: String
    @Binding var showCreateFolder: Bool

    var body: some View {
        // A folder tile carries its folder id in `app.folderId`, but none of the app actions
        // below apply to it: "Move to Root" is a no-op, "Add to Folder" would file a folder UUID
        // as a member, and "Hide App" would persist a junk path.
        if app.isFolder {
            folderActions
        } else {
            appActions
        }
    }

    @ViewBuilder
    private var folderActions: some View {
        if let folderId = app.folderId,
           let folder = appModel.folders.first(where: { $0.id == folderId }) {
            Menu {
                ForEach(folder.appPaths, id: \.self) { appPath in
                    Button {
                        appModel.removeAppFromFolder(appPath, folderId: folderId)
                    } label: {
                        Label("Remove \(appPath.components(separatedBy: "/").last ?? appPath)", systemImage: "minus.circle")
                    }
                }
            } label: {
                Text("Manage Folder Contents")
            }
            Divider()
            Button(role: .destructive) {
                appModel.deleteFolder(folderId: folderId)
            } label: {
                Label("Delete Folder", systemImage: "trash")
            }
        }
    }

    private func moveToOtherFolderMenu(from folderId: String) -> some View {
        Menu("Move to Other Folder") {
            ForEach(appModel.folders, id: \.id) { folder in
                Button {
                    appModel.moveAppInFolder(app.path, from: folderId, to: folder.id)
                } label: {
                    Text("Move to \(folder.name)")
                }
            }
        }
    }

    @ViewBuilder
    private var appActions: some View {
        if !app.isFolder {
            Button {
                let parentPath = (app.path as NSString).deletingLastPathComponent
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: parentPath)])
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
        }
        Button {
            selectedAppPathsForFolder = [app.path]
            newFolderName = String(localized: "Folder")
            showCreateFolder = true
        } label: {
            Label("Add to Folder", systemImage: "folder.badge.plus")
        }
        .disabled(appModel.currentFolderId != nil)
        if !appModel.folders.isEmpty && app.folderId == nil {
            Menu("Add to Existing Folder") {
                ForEach(appModel.folders, id: \.id) { folder in
                    Button {
                        appModel.addAppToFolder(app.path, folderId: folder.id)
                    } label: {
                        Text("Add to \(folder.name)")
                    }
                }
            }
            .disabled(appModel.currentFolderId != nil)
        }
        if let folderId = app.folderId {
            Button(role: .destructive) {
                appModel.moveAppToRoot(app.path, folderId: folderId)
            } label: {
                Label("Move to Root", systemImage: "arrow.up.right")
            }
            if !appModel.folders.isEmpty && appModel.currentFolderId != nil && folderId != appModel.currentFolderId {
                moveToOtherFolderMenu(from: folderId)
            } else if !appModel.folders.isEmpty && appModel.currentFolderId != nil {
                moveToOtherFolderMenu(from: folderId)
            }
        }
        Button {
            appModel.toggleHiddenApp(app.path)
        } label: {
            Label(appModel.isAppHidden(app.path) ? "Show App" : "Hide App", systemImage: appModel.isAppHidden(app.path) ? "eye" : "eye.slash")
        }
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(app.path, forType: .string)
        } label: {
            Label("Copy Path", systemImage: "doc.on.doc")
        }
    }
}
