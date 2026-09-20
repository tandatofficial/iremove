import SwiftUI

struct AppModel: Identifiable {
    let id: String // Bundle ID
    var name: String
    let path: String
    var isHidden: Bool
}

struct ContentView: View {
    @State private var appList: [AppModel] = []
    @State private var searchText: String = ""
    @State private var selectedApp: AppModel?
    @State private var renameTargetName: String = ""
    @State private var isShowingRenameSheet: Bool = false
    @State private var statusMessage: String = ""
    @State private var isShowingStatus: Bool = false

    var filteredApps: [AppModel] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return appList
        } else {
            return appList.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.id.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Bar (iOS 14+ compatible)
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("Tìm tên hoặc Bundle ID...", text: $searchText)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(8)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.vertical, 8)

                if appList.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Đang quét danh sách ứng dụng...")
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    List {
                        Section(header: Text("Ứng dụng đã cài đặt (\(filteredApps.count))")) {
                            ForEach(filteredApps) { app in
                                AppRow(
                                    app: app,
                                    onToggleHide: { hide in
                                        let success = RootHelper.hideApp(atPath: app.path, hide: hide)
                                        if success {
                                            statusMessage = hide ? "Đã ẩn: \(app.name)" : "Đã hiện: \(app.name)"
                                            isShowingStatus = true
                                            reloadApps()
                                        }
                                    },
                                    onRename: {
                                        selectedApp = app
                                        renameTargetName = app.name
                                        isShowingRenameSheet = true
                                    }
                                )
                            }
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                }
            }
            .navigationTitle("iRemove")
            .navigationBarItems(
                trailing: Button(action: reloadApps) {
                    Image(systemName: "arrow.clockwise")
                }
            )
            .onAppear(perform: reloadApps)
            .sheet(isPresented: $isShowingRenameSheet) {
                NavigationView {
                    Form {
                        Section(header: Text("Tên ứng dụng mới")) {
                            TextField("Nhập tên mới", text: $renameTargetName)
                        }
                        Section {
                            Button(action: {
                                if let app = selectedApp, !renameTargetName.isEmpty {
                                    let success = RootHelper.renameApp(atPath: app.path, newName: renameTargetName)
                                    isShowingRenameSheet = false
                                    if success {
                                        statusMessage = "Đã đổi tên thành: \(renameTargetName)"
                                        isShowingStatus = true
                                        reloadApps()
                                    }
                                }
                            }) {
                                Text("Lưu thay đổi")
                                    .fontWeight(.bold)
                            }
                        }
                    }
                    .navigationTitle("Đổi tên ứng dụng")
                    .navigationBarItems(
                        leading: Button("Hủy") {
                            isShowingRenameSheet = false
                        }
                    )
                }
            }
            .alert(isPresented: $isShowingStatus) {
                Alert(
                    title: Text("Thông báo"),
                    message: Text(statusMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    func reloadApps() {
        DispatchQueue.global(qos: .userInitiated).async {
            let rawList = RootHelper.getInstalledApps() as? [[String: Any]] ?? []
            let items: [AppModel] = rawList.compactMap { dict in
                guard let id = dict["bundleId"] as? String,
                      let name = dict["name"] as? String,
                      let path = dict["path"] as? String,
                      let isHidden = dict["isHidden"] as? Bool else { return nil }
                return AppModel(id: id, name: name, path: path, isHidden: isHidden)
            }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }

            DispatchQueue.main.async {
                self.appList = items
            }
        }
    }
}

struct AppRow: View {
    let app: AppModel
    let onToggleHide: (Bool) -> Void
    let onRename: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(app.isHidden ? .secondary : .primary)
                Text(app.id)
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }

            Spacer()

            if app.isHidden {
                Text("ĐÃ ẨN")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.2))
                    .foregroundColor(.orange)
                    .cornerRadius(4)
            }

            Menu {
                Button(action: { onToggleHide(!app.isHidden) }) {
                    Label(app.isHidden ? "Hiện trên màn hình" : "Ẩn khỏi màn hình", systemImage: app.isHidden ? "eye" : "eye.slash")
                }
                Button(action: onRename) {
                    Label("Đổi tên ứng dụng", systemImage: "pencil")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 20))
                    .foregroundColor(.accentColor)
                    .padding(.leading, 8)
            }
        }
        .padding(.vertical, 2)
    }
}
