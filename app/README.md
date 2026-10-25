# Lango 客户端

Flutter Android 客户端与 Web 联调界面。模型名称、API Key 和供应商设置只存在服务端；客户端只配置服务器地址与账户。

## 环境与运行

本次验证使用 Flutter 3.47.8 / Dart 3.13.7、JDK 17、Android SDK 36。首次 Android 构建会自动安装插件所需 SDK/NDK，需接受许可证并能访问 Google Maven、Maven Central 与 Android 下载源。

```sh
flutter doctor -v
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter run -d <设备ID>
```

先按 [服务端说明](../server/README.md) 启动 API，再在 App 输入完整 origin，例如 `https://lango.example.com`。不要附加 `/api/v1`、账号、查询参数或 API Key。注册需要管理员生成的邀请码。

### Android 真机

```sh
adb devices
adb reverse tcp:8000 tcp:8000
flutter run -d <设备ID>
```

使用 USB 反向映射时，App 填 `http://127.0.0.1:8000`。模拟器通常使用 `http://10.0.2.2:8000`；同一可信 Wi-Fi 使用电脑局域网 IP，服务端需监听可访问地址。公网必须使用 HTTPS，不关闭证书验证。

Android 清单允许用户自定义局域网 HTTP，并在界面提示明文风险；HTTP 会暴露凭证与对话，不能在不可信网络使用。账户令牌通过 `flutter_secure_storage` 保存；应用备份关闭。录音权限按需请求，拒绝麦克风后仍能打字。

### Web 调试

```sh
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8080
```

服务端 `LANGO_ALLOWED_ORIGINS` 必须包含 `http://127.0.0.1:8080`。Web 麦克风要求 HTTPS 或 localhost；浏览器也可能要求用户交互后才允许音频播放。Web 的凭证保护依赖浏览器 origin 与 WebCrypto，不等同于 Android 硬件密钥存储。不要在共享电脑上保留登录。

## 构建

```sh
flutter build web
flutter build apk --debug
```

产物：`build/web/`、`build/app/outputs/flutter-apk/app-debug.apk`。调试包可用 `adb install -r build/app/outputs/flutter-apk/app-debug.apk` 安装。当前工程的 release 构建也使用开发签名；公开发行前必须由维护者配置自己的签名密钥，不能把开发包当作正式商店签名包。

## 语音行为

- 按住说话：松开提交；过短/纯静音录音取消。
- 自动静音：能量 VAD 与短预录；播放时暂停录音，采用半双工避免外放自激，不宣称全双工回声消除。
- 字幕与音频分开接收；每段音频完整播放后才发确认。生成结束不代表播放结束。
- 打断会停止当前音频、丢弃队列并忽略旧响应；失败音频不会被当作已听过的内容。
- 切到后台暂停录音与播放；恢复后由用户重新开始。断线时丢弃未提交音频，使用新 ticket 恢复原会话，不自动重发录音。
- 历史继续保留原场景和引擎，不重播旧音频。角色扮演不提取为个人经历；暂停记忆保留既有事实，删除才代表遗忘。

## 测试边界

`test/` 覆盖连接页、URL 校验、令牌刷新/切换、记忆暂停、历史恢复、播放确认与取消、权限拒绝和生命周期暂停。录音/播放器单元测试采用替身，不能替代实际手机麦克风、外放回声、蓝牙路由与锁屏测试。完整记录见 [验证说明](../docs/verification.md)。
