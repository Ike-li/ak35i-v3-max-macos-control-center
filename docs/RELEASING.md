# 发布流程

本指南面向维护者，目标是创建可追溯的 macOS 发布包。

## 本地检查

```zsh
swift test --disable-sandbox
./Packaging/create-dmg.sh
hdiutil verify dist/AK35i-Control-Center-*-arm64.dmg
shasum -a 256 dist/AK35i-Control-Center-*-arm64.dmg
```

发布前确认：

- `git status` 干净；
- `git add -n .` 不包含 `artifacts/` 或 `dist/`；
- 文档、日志、截图和二进制中没有序列号、个人路径或令牌；
- Release notes 明确标注硬件范围、架构、macOS 最低版本、已验证功能和未公证状态。

## 创建 GitHub Release

上传 DMG 及同名 `.sha256` 文件。发布后从 GitHub 回下载一次，比较 SHA-256 并再次运行 `hdiutil verify`。

## 稳定版门槛

在将预览版标为稳定版前，至少应完成：

1. Apple Developer ID 签名与公证；
2. 已支持架构的真机启动验证；
3. Release 资产回下载和校验；
4. README、协议状态和变更说明同步更新。
