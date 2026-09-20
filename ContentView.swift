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
    
    // Alert States
    @State private var isShowingSuccessAlert: Bool = false
    @State private var successAlertMessage: String = ""
    @State private var isShowingErrorAlert: Bool = false
    @State private var errorAlertMessage: String = ""

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
                // Search Bar
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
                                        let err = RootHelper.hideApp(atPath: app.path, bundleID: app.id, hide: hide)
                                        if let err = err {
                                            self.errorAlertMessage = err
                                            self.isShowingErrorAlert = true
                                        } else {
                                            reloadApps()
                                            self.successAlertMessage = hide ? "Đã đặt cờ ẩn cho '\(app.name)' thành công!" : "Đã hủy cờ ẩn cho '\(app.name)' thành công!"
                                            self.isShowingSuccessAlert = true
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
                    .alert(isPresented: $isShowingErrorAlert) {
                        Alert(
                            title: Text("Thông báo lỗi"),
                            message: Text(errorAlertMessage),
                            dismissButton: .default(Text("Đóng"))
                        )
                    }
                }
            }
            .navigationTitle("iRemove")
            .navigationBarItems(
                leading: Button(action: {
                    RootHelper.respring()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                        Text("Respring")
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.orange)
                },
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
                                    let err = RootHelper.renameApp(atPath: app.path, bundleID: app.id, newName: renameTargetName)
                                    isShowingRenameSheet = false
                                    if let err = err {
                                        self.errorAlertMessage = err
                                        self.isShowingErrorAlert = true
                                    } else {
                                        reloadApps()
                                        self.successAlertMessage = "Đã đổi tên thành '\(renameTargetName)' thành công!"
                                        self.isShowingSuccessAlert = true
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
            .alert(isPresented: $isShowingSuccessAlert) {
                Alert(
                    title: Text("Thao tác thành công"),
                    message: Text(successAlertMessage + "\n\nBạn có muốn Respring ngay để SpringBoard cập nhật màn hình chính?"),
                    primaryButton: .destructive(Text("⚡ Respring ngay")) {
                        RootHelper.respring()
                    },
                    secondaryButton: .default(Text("Để sau"))
                )
            }
        }
    }

    func reloadApps() {
        DispatchQueue.global(qos: .userInitiated).async {
            RootHelper.escalatePrivileges()
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
