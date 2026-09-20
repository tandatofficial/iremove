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
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @State private var isShowingAlert: Bool = false
    @State private var isShowingRespringConfirm: Bool = false

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
                                            showAlert(title: "Lỗi thực hiện", message: err)
                                        } else {
                                            reloadApps()
                                            showRespringPrompt(message: hide ? "Đã đặt cờ ẩn cho '\(app.name)'. Hãy Respring để SpringBoard xóa icon ngay lập tức." : "Đã hủy cờ ẩn cho '\(app.name)'. Hãy Respring để hiện lại icon.")
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
                leading: Button(action: { isShowingRespringConfirm = true }) {
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
                                        showAlert(title: "Lỗi đổi tên", message: err)
                                    } else {
                                        reloadApps()
                                        showRespringPrompt(message: "Đã đổi tên thành '\(renameTargetName)'. Hãy Respring để SpringBoard áp dụng tên mới.")
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
            .alert(isPresented: $isShowingAlert) {
                Alert(
                    title: Text(alertTitle),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
            .actionSheet(isPresented: $isShowingRespringConfirm) {
                ActionSheet(
                    title: Text("Khởi động lại SpringBoard (Respring)"),
                    message: Text("Respring sẽ làm mới màn hình chính trong 1-2 giây để áp dụng ngay icon và tên mới."),
                    buttons: [
                        .destructive(Text("Respring ngay"), action: {
                            RootHelper.respring()
                        }),
                        .cancel(Text("Hủy"))
                    ]
                )
            }
        }
    }

    func showAlert(title: String, message: String) {
        self.alertTitle = title
        self.alertMessage = message
        self.isShowingAlert = true
    }

    func showRespringPrompt(message: String) {
        self.alertTitle = "Thao tác thành công"
        self.alertMessage = message
        self.isShowingRespringConfirm = true
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
