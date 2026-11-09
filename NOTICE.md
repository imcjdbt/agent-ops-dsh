# 出处与致谢

## 原作

本项目使用的视觉设计、页面结构与交互，来自：

- **项目**：[cyberdaddyleo / agent-display](https://github.com/cyberdaddyleo/agent-display)
- **作者**：赛博老爸（Cyber Daddy Leo）
- **许可**：PolyForm Noncommercial 1.0.0
- **版权声明**：`Required Notice: Copyright (c) 2026 赛博老爸`
- **联系方式**：cyberdaddyleo@outlook.com

原项目是一个纯前端的 AI 智能体调度可视化大屏，包含 10 套主题，所有数据均为内置模拟。`index.html` 的视觉部分原样保留，页面上的 `DEVELOPED BY @赛博老爸` 水印也原样保留。

## 本仓库做的改动

本仓库（imcjdbt）在原作基础上做了本地化封装，**没有改动画面的任何布局、尺寸、层级、间距或字体规格**，只替换文字与数值，并补充运行脚本：

1. **数据接入**：新增 `live/bridge.mjs`，读取本机 `%USERPROFILE%\.dsh` 下的账本与会话日志，把 OPS 主题里原本的模拟数据替换为真实数据（会话、token、缓存命中、花费、工具调用流水）
2. **主题扩充**：在原有「粒子 / 纸面」之外新增第三档「墨底」，并改为单按钮循环切换
3. **配色面板**：新增两色取色器（背景 / 文字），其余颜色变量按比例派生
4. **Lively 封装**：新增 `lively.html`、`LivelyInfo.json`、`install.ps1` 等，使其能作为 Windows 动态壁纸一键安装
5. **移除按钮**：去掉了 OPS 页面右上角的「换主题」「全屏」两个按钮（壁纸场景用不到）

## 许可

本仓库整体沿用 **PolyForm Noncommercial 1.0.0**（见 `LICENSE`）：

- 个人、学习、研究等**非商业用途免费**
- **商业用途需向原作者取得授权**（cyberdaddyleo@outlook.com）
- 分发时必须保留 `LICENSE` 与页面上原有的版权声明

如果你 fork 或二次分发，请同样保留本文件与 `LICENSE`。

---

# Credits & Notice (English)

## Original work

The visual design, page structure and interaction come from:

- **Project**: [cyberdaddyleo / agent-display](https://github.com/cyberdaddyleo/agent-display)
- **Author**: 赛博老爸 (Cyber Daddy Leo)
- **License**: PolyForm Noncommercial 1.0.0
- **Notice**: `Required Notice: Copyright (c) 2026 赛博老爸`
- **Contact**: cyberdaddyleo@outlook.com

The original is a pure front-end dashboard for AI-agent orchestration with 10 themes; every number in it is simulated. The visual part of `index.html` is kept intact, and the `DEVELOPED BY @赛博老爸` watermark on the page is preserved.

## What this repository changes

This repository (imcjdbt) wraps the original work locally. **No layout, size, stacking order, spacing or font metric was changed** — only text and values were replaced, plus new runtime scripts:

1. **Data wiring**: a new `live/bridge.mjs` reads the ledger and session logs under `%USERPROFILE%\.dsh` and replaces the simulated OPS figures with real ones (sessions, tokens, cache hits, spend, tool-call stream)
2. **Third theme**: "Ink" added next to the original Particles / Paper, with a single cycling button
3. **Color panel**: a two-color picker (background / text); the remaining variables derive proportionally
4. **Lively packaging**: `lively.html`, `LivelyInfo.json`, `install.ps1` and friends, so it installs as a Windows live wallpaper
5. **Removed buttons**: the OPS "switch theme" and "fullscreen" buttons (useless on a wallpaper)

## License

This repository stays under **PolyForm Noncommercial 1.0.0** (see `LICENSE`):

- Free for personal, educational and research use
- **Commercial use requires permission from the original author** (cyberdaddyleo@outlook.com)
- Redistribution must keep `LICENSE` and the original copyright notice

If you fork or redistribute, keep this file and `LICENSE` as well.
