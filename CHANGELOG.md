# Changelog

## 0.1.1 (2026-09-30)

- Avoid a Computer Use helper crash when inspecting target preview cards by rendering their titles inside the group, with accessible heading semantics.
- Preserve all target controls and configuration behavior.

## 0.1.0 (2026-09-30)

- First public GitHub and npm release under the MIT license.
- Universal macOS 13+ app for Apple Silicon and Intel.
- Supports Terminal, VS Code, and Claude Code; removes Cursor integration.
- Fixes JSONC parsing for comments, field order, escapes, and trailing commas; rejects duplicate or malformed environment entries without overwriting settings.
- Aligns Claude Code apply reports with profile overlay behavior.
- Preserves existing profiles when index metadata is missing.
- Rejects malformed Claude environment values without overwriting settings.
- Reports settings read errors instead of treating unreadable files as empty.
- Replaces internal publishing tools with public npm packaging and GitHub Actions.


## 0.0.2 (2026-04-07)

**功能变更**
- 添加 DMG 构建脚本，支持 macOS 应用打包
- macOS 构建时自动生成应用图标
- 项目重构为核心层、应用层和可执行层
- 支持环境中的额外托管密钥
- 添加备份清单和调试目标数据生成器
- 迁移至配置目录，支持 zshrc hook 和环境文件管理
- 改进配置文件匹配和 UI，增强冲突检测能力
- 添加调试模式和改进应用确认界面
- 优先选择检测到的当前配置文件
- 支持配置文件匹配状态和不同步状态展示
- 重新设计应用确认工作表
- 迁移配置文件至基于目录的结构

**修复**
- 扩展备份保留时间

**重构**
- 将托管 shell 环境文件扩展名改为 .sh，改进目标预览逻辑
- 移除索引模式中的默认配置文件 ID
- 将配置文件配置分割为索引和文件两部分
- 项目重命名为 cc-env-switcher

**文档**
- 架构文档中文翻译
- 文档结构重组和清理未使用文件
- 简化 macOS 发行指南
- 添加当前配置文件状态设计和实现规范
- 添加应用确认工作表设计规范
- 添加主屏幕排版设计规范
- 添加未跟踪当前密钥演示规范

**测试**
- 添加应用确认选择逻辑

**其他**
- 更新包版本和发布配置
- 更新包名称
- 更新 VSCode 调试配置目标名称
- 当工具链不可用时跳过 Swift 构建
- 从模板初始化项目
