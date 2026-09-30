# macOS 分发

`npm run build:app` 构建 macOS 13+ 的 arm64 / x86_64 通用二进制，生成
`build/artifacts/cc-env-switcher.app`。版本来自根目录 `package.json`。

`npm run build:dmg` 将应用和 README 打包到 `build/artifacts/cc-env-switcher.dmg`。
`npm run assemble` 生成公开 npm 包目录 `publish/`，包含原生应用和 Node.js 启动器。
安装时不执行脚本，也不下载或编译二进制。

默认使用 ad-hoc 签名，不包含 Developer ID 或 Apple 公证。它提供代码签名完整性检查，
不代表 Apple 已核验开发者身份或批准分发。下载的 DMG 可能触发 Gatekeeper 拦截，
用户应先确认来源，再自行决定是否在系统设置中允许打开；不要自动清除隔离属性。

有 Developer ID 后可设置 `CODE_SIGN_IDENTITY` 构建带 hardened runtime 与时间戳的应用；
公证仍需要单独提交和核验，不因设置签名证书而自动完成。

发布步骤见 [CONTRIBUTING.md](../CONTRIBUTING.md)。
