# Reader (macOS)

一个面向 Apple Silicon 的 macOS 电子书阅读器，主打一个上班摸鱼功能。
完全透明，无菜单栏，除了电子书内容文字没有任何其他东西。
<img width="1236" height="730" alt="image" src="https://github.com/user-attachments/assets/b0adc5cf-ee10-482e-8660-1e1b649e3d2a" />

- 支持格式：`txt`、`pdf`、`epub`、`mobi`、`azw3`
- 支持透明模式、全文检索、目录跳转、返回上一个位置
- 首页持久化书目（仅记录本地路径，不复制原文件）
- 记住阅读进度（文本滚动比例 / PDF 页码）

## 1. 当前功能

### 1.1 导入与书库
- 首页支持多选导入文件
- 支持从首页移除书目（不会删除本地文件）
- 重启应用后，已导入书目仍会显示

### 1.2 阅读模式
- 主阅读窗口使用隐藏标题栏，保持尽量干净的阅读视图
- 文本类（TXT/EPUB/MOBI/AZW3/PDF 文本模式）支持：
  - 字号调整
  - 字体颜色（黑/白）
- PDF 支持两种模式：
  - `PDF Original Layout`
  - `PDF Text Mode`（提取可选中文本后按文本阅读）

### 1.3 透明模式
- 一键开关透明模式
- 透明度可调（50% 到 100%）

### 1.4 全文检索（Cmd+F）
- 独立可拖动检索窗口
- 支持当前已打开书籍的全文检索
- 点击检索结果自动跳转到命中位置
- 检索结果中关键字高亮显示
- 跳转前自动记录当前位置，可用“返回上一个位置”回退

### 1.5 目录（Cmd+T）
- 独立可拖动目录窗口
- 点击目录项自动跳转
- 跳转前自动记录当前位置，可回退
- 目录来源：
  - `epub/mobi/azw3`：优先使用书内目录（NCX）
  - `pdf`：使用 PDF Outline/书签
  - `txt`：按常见章节标题规则自动识别（如“第X章/第X幕/序幕/尾声/Chapter”等）

### 1.6 返回上一个位置（Cmd+[）
- 适用于：
  - 内部链接跳转
  - 全文检索跳转
  - 目录跳转

## 2. 快捷键

在菜单 `Reader` 中可见：

- `Cmd+Shift+H`：返回主页
- `Cmd+[`：返回上一个位置
- `Cmd+F`：打开全文检索窗口
- `Cmd+T`：打开目录窗口
- `Cmd+Shift+T`：切换透明模式
- `Cmd+Option+]`：透明度 +10%
- `Cmd+Option+[`：透明度 -10%
- `Cmd+=`：字号 +2
- `Cmd+-`：字号 -2

## 3. 环境要求

- macOS（Apple Silicon）
- Xcode 15+
- `xcodegen`

可选（仅 `mobi/azw3` 必需）：
- Calibre CLI：`ebook-convert`
  - 常见路径：
    - `/Applications/calibre.app/Contents/MacOS/ebook-convert`
    - `/opt/homebrew/bin/ebook-convert`
    - `/usr/local/bin/ebook-convert`

## 4. 快速开始

### 4.1 生成工程
```bash
xcodegen generate
```

### 4.2 打开工程并运行
```bash
open Reader.xcodeproj
```

在 Xcode 中选择 `Reader` scheme，`Cmd+R` 运行。

### 4.3 命令行构建（可选）
```bash
xcodebuild -project Reader.xcodeproj -scheme Reader -configuration Debug build
```

## 5. 打包为 .app

最直接方式：
1. 在 Xcode 里 `Product -> Build`（或 `Cmd+B`）
2. 在 `DerivedData/Build/Products/Debug` 或 `Release` 目录获取 `Reader.app`

发布建议（后续可做）：
- 使用 `Archive` + `Developer ID` 签名 + Notarization

## 6. 数据存储位置

应用会在 `Application Support/Reader` 下保存：
- `library_catalog.json`：书库列表（标题、路径、格式）
- `reading_progress.json`：阅读进度

说明：
- 仅保存本地文件路径，不复制电子书文件
- 若原文件移动/删除，书库记录会失效

## 7. 项目结构

```text
App/                    # 入口、窗口、路由、命令菜单
Core/                   # 领域模型、导入服务、本地存储
Features/               # Library/Reader 业务界面与交互
Infrastructure/         # 平台适配（macOS）
Resources/              # 资源（AppIcon 等）
Scripts/                # 脚本（如图标生成）
project.yml             # XcodeGen 配置
```

## 8. 关键设计说明

- 阅读窗口保持极简：不在正文界面内堆按钮
- 检索与目录均采用独立窗口（可拖动）
- 统一“跳转前记录位置”策略，保障回退体验一致

## 9. 已知限制

- `txt` 目录为规则识别，复杂排版文本可能识别不全
- `pdf` 文本模式依赖 PDF 可选中文本质量；扫描版可能无有效文本
- `mobi/azw3` 导入依赖 Calibre CLI

## 10. 开发备注

### 10.1 重新生成 App 图标
```bash
swift Scripts/generate_app_icon.swift
```

### 10.2 变更 `project.yml` 后
```bash
xcodegen generate
```

---

如果你希望继续迭代，优先建议：
- 目录搜索（按目录标题过滤）
- 检索结果的“上一个/下一个”快捷键导航
- TXT 目录识别规则配置化
