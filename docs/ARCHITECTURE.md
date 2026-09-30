# 架构说明

## 模块结构

项目由三个 SPM target 组成，依赖关系严格单向：

```
CCEnvSwitcherExecutable  （应用入口）
        └── CCEnvSwitcherApp  （SwiftUI 界面层）
                └── CCEnvSwitcherCore  （领域库）
```

- **CCEnvSwitcherCore** — 模型、服务、协议、各目标写入器。无外部依赖。
- **CCEnvSwitcherApp** — `AppViewModel` 及全部 SwiftUI 视图。依赖 Core。
- **CCEnvSwitcherExecutable** — `@main` App 结构体与 `AppDelegate`，负责启动引导。

## 核心抽象

### `TargetWriter` 协议

每个环境写入目标均须实现此协议：

```swift
protocol TargetWriter {
    var target: TargetKind { get }
    var fileURL: URL { get }

    func currentManagedEnvironment() throws -> [String: String]
    func preview(for profile: ClaudeProfile) throws -> TargetPreview
    func apply(profile: ClaudeProfile, backupService: BackupService, backupRun: BackupRun) throws -> TargetPreview
}
```

当前实现：

| 类 | 目标文件 |
|----|---------|
| `ZshrcTarget` | `~/.zshrc` + `env.sh` |
| `JSONCEnvironmentTarget` | VSCode 的 `settings.json` |
| `ClaudeSettingsTarget` | `~/.claude/settings.json` |

### `ApplyService`

负责协调整个 profile 应用流程：

1. 创建带时间戳的 `BackupRun` 目录
2. 依次调用每个 `TargetWriter` 的 `apply()`，捕获并记录错误
3. 写入备份清单
4. 仅在全部写入成功后才持久化 `state.json`

`ApplyService` 通过工厂方法构造，以便 `AppViewModel` 在切换调试模式时传入不同的路径配置。

### `AppViewModel`

`@MainActor @ObservableObject`，是界面层与 Core 层之间唯一的协调者。

主要职责：
- 加载配置，检测当前已应用的 profile
- 为确认弹窗生成 `TargetPreview` 列表
- 用户确认后驱动 `ApplyService` 执行写入
- 切换调试模式（重新创建指向调试路径的 `ApplyService`）
- 展示 `.zshrc` 冲突警告和重复 profile 警告

## 数据流：应用一个 Profile

```
用户点击 Apply
  → AppViewModel.prepareApplySelectedProfile()
      → ApplyService.preview()  [只读，不写文件]
      → 弹出确认界面，展示 TargetPreview 列表

用户确认
  → AppViewModel.confirmApplySelectedProfile()
      → ApplyService.apply(profile)
          → 对每个 TargetWriter：
              读取当前环境 → 合并 profile 环境变量 → 备份原文件 → 写入新文件
          → 写入 manifest.json
          → 保存 state.json
      → AppViewModel 刷新状态、预览、警告
```

## 持久化

| 数据 | 路径 | 格式 |
|------|------|------|
| Profile 文件 | `{root}/profiles/{id}.json` | JSON（`ProfileConfiguration`） |
| Profile 索引 | `{root}/profiles/index.json` | `{ "version": 1 }` |
| 应用状态 | `{root}/state.json` | `{ lastAppliedProfileId, lastAppliedAt }` |
| 备份 | `{root}/backups/{timestamp}/` | 原始文件副本 + `manifest.json` |

存储根目录解析优先级：`CC_ENV_SWITCHER_HOME` → `XDG_CONFIG_HOME/cc-env-switcher` → `~/.config/cc-env-switcher`。

### 备份保留策略

每个目标最多保留 20 份备份，超出后删除最旧的。每次备份运行会生成一个 `manifest.json`，记录各目标的写入状态：`backed_up`、`created_without_backup`、`unchanged`、`failed`。

## 目标文件

### 系统模式与调试模式

`AppPaths` 提供两套路径配置。调试模式下，所有目标均重定向到 `{root}/debug/`，文件名加 `debug.` 前缀。切换模式时 `ApplyService` 随之重建。

| 目标 | 系统模式 | 调试模式 |
|------|---------|---------|
| Shell rc | `~/.zshrc` | `debug/debug.zshrc` |
| Shell 环境变量 | `{root}/env.sh` | `debug/debug.env.sh` |
| VSCode | `~/Library/.../Code/User/settings.json` | `debug/debug.vscode.settings.json` |
| Claude | `~/.claude/settings.json` | `debug/debug.claude.settings.json` |

### 各目标的写入行为

**`ZshrcTarget`**：仅在 `~/.zshrc` 中维护一行 source 钩子（`source … env.sh`），其余内容不作任何改动。`env.sh` 由应用全权管理，每次写入均完整替换为 `export KEY="VALUE"` 格式的内容。历史遗留的托管块在首次应用时自动清除。

**`JSONCEnvironmentTarget`**：将托管条目合并写入 `claudeCode.environmentVariables` 数组——托管键更新或追加，非托管键保留不动。JSONC 文件中的注释在重写后会丢失。

**`ClaudeSettingsTarget`**：仅修改 `env` 字典，文件中其他所有顶层键（model、hooks、permissions 等）一律保留。

## 托管键

在 `ManagedEnvironment` 中定义：

- 显式有序键（优先输出）：`API_TIMEOUT_MS`
- 显式键：`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`
- 前缀匹配：`ANTHROPIC_*`、`CLAUDE_CODE_*`

Profile 中的非托管键会被保存，但不会写入系统文件。显示顺序：显式有序键 → 其余托管键（字母序）→ 未托管键（带删除线）。

## 设计决策

- **全面使用值类型** — 所有模型和写入器均为 `struct`，可安全跨 `Task` 传递。
- **协议驱动的目标扩展** — 新增写入目标无需修改 `ApplyService`。
- **预览与应用的对称性** — 两者均返回 `TargetPreview`；预览是真正的只读空运行，应用时重新计算而非回放预览结果。
- **原子性状态保存** — 仅在全部三个写入器均成功后才写入 `state.json`。
- **可测试的工厂模式** — `BackupService` 接受注入的 `dateProvider`；`ApplyService` 通过构造参数接收写入器列表，从而在不触及文件系统的情况下完成单元测试。
