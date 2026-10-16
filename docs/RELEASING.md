# 发布流程

本指南面向维护者。

## 准备

1. 更新 `Packaging/Info.plist` 的 `CFBundleShortVersionString`（例如 `0.2.0`），并递增 `CFBundleVersion`。
2. 同步 README、[功能与协议状态](PROTOCOL_STATUS.md) 等文档。
3. 本地检查：

   ```zsh
   swift test --disable-sandbox
   zsh Packaging/create-dmg.sh
   hdiutil verify dist/AK35i-Control-Center-*-universal.dmg
   lipo -archs "dist/AK35i Control Center.app/Contents/MacOS/ak35i"   # 应输出 x86_64 arm64
   ```

4. 确认 `git status` 干净；文档、截图和二进制里没有设备序列号、个人路径、所在时区或令牌。

## 打标签发布

```zsh
git tag v0.2.0
git push origin main v0.2.0
```

推送 `v*` 标签后，[`release.yml`](../.github/workflows/release.yml) 会在 macOS 15 上依次执行：跑测试、生成 Intel 与 Apple Silicon 通用的 DMG 和 `.sha256`、检查应用能启动，最后建立草稿 Release。标签必须与 `Info.plist` 的版本一致，否则工作流会失败。

发布草稿前，在说明里写清：

- 支持的硬件（AK35i V3 Max，`0C45:8009`）和 macOS 最低版本；
- 已验证和实验性的功能；
- 发布包没有经过 Apple 公证，首次打开需要在“隐私与安全性”里点“仍要打开”。

## 发布后

从 GitHub 下载一次，用 `shasum -a 256 -c` 校验，再在一台 Mac 上按 [快速上手](GETTING_STARTED.md) 的步骤安装并打开。

## 公证（可选）

如果之后加入 Apple Developer Program，可以在工作流里用 Developer ID 证书签名，再用 `xcrun notarytool` 公证、`xcrun stapler` 装订，用户就不需要手动允许。证书和密码放在仓库 Secrets 里，不要提交到仓库。
