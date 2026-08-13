import SwiftUI

struct AppContextMenu: View {
    @Bindable var appModel: AppModel
    let app: Application
    @Binding var selectedAppPathsForFolder: [String]
    @Binding var newFolderName: String
    @Binding var showCreateFolder: Bool

    var body: some View {
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
                Menu("Move to Other Folder") {
                    ForEach(appModel.folders, id: \.id) { folder in
                        Button {
                            appModel.moveAppInFolder(app.path, from: app.folderId!, to: folder.id)
                        } label: {
                            Text("Move to \(folder.name)")
                        }
                    }
                }
            } else if !appModel.folders.isEmpty && appModel.currentFolderId != nil {
                Menu("Move to Other Folder") {
                    ForEach(appModel.folders, id: \.id) { folder in
                        Button {
                            appModel.moveAppInFolder(app.path, from: app.folderId!, to: folder.id)
                        } label: {
                            Text("Move to \(folder.name)")
                        }
                    }
                }
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

struct FolderContextMenu: View {
    @Bindable var appModel: AppModel
    let app: Application
    @Binding var newFolderName: String
    @Binding var selectedAppPathsForFolder: [String]
    @Binding var showCreateFolder: Bool

    var body: some View {
        if let folderId = app.folderId {
            if let folder = appModel.folders.first(where: { $0.id == folderId }) {
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
                Button {
                    newFolderName = folder.name
                    selectedAppPathsForFolder = []
                    showCreateFolder = true
                } label: {
                    Label("Rename Folder", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    appModel.deleteFolder(folderId: folderId)
                } label: {
                    Label("Delete Folder", systemImage: "trash")
                }
            }
        } else {
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
            if !appModel.folders.isEmpty {
                Menu {
                    ForEach(appModel.folders, id: \.id) { folder in
                        Button {
                            appModel.addAppToFolder(app.path, folderId: folder.id)
                        } label: {
                            Text("Add to \(folder.name)")
                        }
                    }
                } label: {
                    Label("Add to Existing Folder", systemImage: "folder")
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
}
