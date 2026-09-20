# iRemove - TrollStore App

Ứng dụng ẩn icon, đổi tên và đổi icon cho các app đã cài trên iOS thông qua **TrollStore** (tương tự iPurge) mà không làm ảnh hưởng đến dữ liệu hay chứng chỉ của ứng dụng gốc.

## Tính năng chính:
- **Ẩn app khỏi màn hình chính (SpringBoard)**: Chỉnh sửa `SBAppTags = ("hidden")` và gọi `uicache`.
- **Đổi tên ứng dụng**: Cập nhật `CFBundleDisplayName` & `CFBundleName`.
- **Đổi icon ứng dụng**: Thay thế icon bundle và trỏ `CFBundleIcons`.
- **TrollStore Unsandboxed/Root**: Tự động bypass sandbox qua entitlements đặc quyền (`no-sandbox`, `platform-application`).

## Tự động đóng gói IPA qua GitHub Actions:
Kho lưu trữ đã được cấu hình sẵn CI/CD trong `.github/workflows/build.yml`. Mỗi khi push code lên GitHub, GitHub Actions sẽ tự động:
1. Setup môi trường macOS runner & clang/swiftc arm64
2. Biên dịch source Swift + Obj-C RootHelper
3. Ký `entitlements.plist` với `ldid`
4. Đóng gói ra file `iRemove.ipa` và đính kèm vào mục Artifacts / Releases để tải về cài trực tiếp vào TrollStore.
