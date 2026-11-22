# 贡献指南

感谢你愿意让 nas_client 变得更好。无论是修一个错别字、补一段文档，还是实现新协议，都欢迎。

## 开始前

1. 先读一遍 [README.md](README.md)，尤其是「架构与目录」「协议与实现细节」「局限」三节，避免重复实现已有的回退与缓存逻辑。
2. 在动手写较大的功能前，先开一个 Issue 说明动机和大致方案。小修复可以直接提 Pull Request。
3. 本项目以中文交流为主，代码注释与提交信息可用中文或英文，保持清晰即可。

## 开发环境

| 项目 | 要求 |
| --- | --- |
| Flutter | stable，`pubspec.yaml` 中 `environment.sdk` 指定的版本或更新的兼容版本 |
| Dart | 随 Flutter SDK 提供 |
| Android SDK | 与 Flutter 自带的 `compileSdkVersion` / `ndkVersion` 匹配 |
| 设备 | 一台开启 USB 或无线调试的 Android 手机，以及同一局域网内的 SMB / FTP 服务器 |

```bash
flutter pub get
flutter devices
flutter run
```

## 提交代码前

请在本机全部跑通：

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

- `flutter analyze` 不允许出现新的 error 或 warning。
- 新增的纯逻辑（网段计算、路径、协议回退、字节范围、缓存策略等）请补进 `test/core_test.dart`，尽量写成不依赖真实服务器的单元测试。
- 涉及网络的功能请说明测试用的服务器类型与协议版本，方便复现。

## 提交与 Pull Request

- 提交信息简洁描述改动，例如 `fix: 取消下载后删除半成品文件`。
- 一个 Pull Request 聚焦一件事，改动较大时附上前后对比或复现步骤。
- 不要提交任何密钥、签名文件、`android/key.properties`、`android/local.properties`、构建产物或个人服务器地址与账号。这些路径已在 `.gitignore` 中排除，请再检查一次 `git status`。
- 在描述里注明是否需要真机验证，以及验证过的 Android 版本。

## 设计约定

- 界面配色统一通过 `AppPalette` 取用，不要在页面里硬编码颜色；白天/夜间都要能看清。
- 网络与文件操作放在 `lib/services/`，可复用纯函数放在 `lib/utils/`，UI 组件放在 `lib/widgets/`。
- 长时间操作必须支持取消，且在取消时清理临时文件、释放服务器连接。
- SMB 单块读写目前以约 64 KB 为上限，调整前请先阅读 README 中的说明。

## 行为约定

保持友善、就事论事。维护者可能会要求调整实现方式或拆分 PR，这是为了保证项目长期可维护，不是针对个人。

## 许可证

向本项目提交内容，即表示你同意该内容以 [MIT 许可证](LICENSE) 发布。
