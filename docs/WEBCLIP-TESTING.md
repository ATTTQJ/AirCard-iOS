# AirCard WebClip 实验版

基于 Mak5er/AirCard-iOS。保留上游 MIT 许可证及作者署名。

新增 WebClip 页面只对 **iOS 27.0.1** 开放设备写入。构建成功不代表实机功能已验证。

## 安装

从 GitHub Actions 的 `AirCard-WebClip-unsigned-编号` artifact 下载 ZIP，解压得到 IPA。
这是未签名的设备版 IPA，需要用自己的有效签名方式安装。
应用名称为 **AirCard WebClip**，Bundle ID 为 `com.atttqj.aircard.webclip`，可与原版并存。
在本实验版内重新导入本机配对文件或完成配对，并按上游说明启用 LocalDevVPN。
配对文件留在手机上，不要上传到仓库、Actions 或 issue。

## 首次测试

1. 先制作完整设备备份，确保照片和重要聊天记录另有可用副本。
2. 打开“图标主题”，输入已安装 App 的真实 Bundle ID、桌面名称并选择图片。
   微信官方包通常为 `com.tencent.xin`；自签包以实际 Bundle ID 为准。
3. 预览后新增一个图标，保持应用在前台。不要同时操作钱包、壁纸或密码主题。
4. 返回成功仅表示 AirLift 接口完成，不代表文件已读回验证、图标已注册或 App 启动正常。
5. 选择“刷新桌面”或手动重启手机，然后检查：图标显示、目标 App 启动、快捷指令提示、重启后保留。
6. 尝试长按新增图标删除书签；不要删除原 App。若不显示或不能删除，保留写入记录，不要连续重试。

## 实现范围

- 在本机生成 `Info.plist` 和标准化的 180×180 PNG。
- 使用直接关联已安装应用的 `ApplicationBundleIdentifier`，不生成 URL 或快捷指令。
- 调用上游 `al_exploit_inject_folder`，固定写入 `/var/mobile/Library/WebClips/` 下新建的随机 UUID 文件夹。
- 不接受任意路径、不覆盖旧书签、不编辑桌面布局数据库、不调用备份恢复或抹机流程。
- 上游 AirLift 传输仍会使用临时 Media/Books 同步文件，不能将其称为“完全不改其他文件”或零风险。
- 写入前持久化操作记录，失败不自动重试，刷新桌面需要单独操作。
- 第一个版本不提供 App 自动枚举、批量导入、原位更新或系统文件删除。

## 尚待验证

WebClips 目录在 27.0.1 上是否可由 AirLift 写入、目录权限、SpringBoard 是否发现新增书签、
App 是否直接启动、手动删除及重启后的行为均需实机验证。
错误或中断可能留下部分文件。没有实机数据，不能给出成功率或保证数据不会丢失。

## 构建

GitHub Actions 在 macOS 上运行 XcodeGen，检查 payload/path/version gate，然后编译设备版 IPA。
不需要开发者证书或仓库 secrets。不要把证书、密码或配对文件加入工作流。

本地 macOS：

```sh
brew install xcodegen
xcodegen generate
swiftc ios-app/WebClipSpec.swift scripts/check-webclip.swift -o /tmp/check-webclip
/tmp/check-webclip
bash build-ipa.sh Release
```

图标关联机制参考 GoldenNugget / Cowabunga 的 WebClip 格式。
本分支独立实现 Swift payload 生成和界面，复用 AirCard 原有 AirLift 库。
