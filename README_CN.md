<div align="center">

# astra-glow

**一眼扫过终端，就知道每个 AI agent 在干嘛——一个字都不用读。**

Ghostty 里的 AI agent 环境状态灯：GPU 渲染的极光、萤火虫、琥珀波浪和骷髅头，由 agent 生命周期 hooks 驱动，零 token 成本。

[English](README.md)

</div>

---

## 效果

| 状态 | 触发 | 特效 |
|---|---|---|
| 🌀 **正在跑** | 你发出 prompt | 暗色极光流彩 + 星尘 |
| 🟢 **完成待看** | agent 跑完 | 翡翠呼吸 + 雾浪 + 上浮萤火虫 |
| 🟠 **等你** | 完成 10 分钟没理 / agent 等授权 | 琥珀呼吸 + 层叠波浪 + 粒子 |
| 💀 **翻车** | agent 报错 | 骷髅头（红瞳脉动）+ 余烬 + 暗角 |

在窗口里回复 → 还原主题原色。agent 退出或 crash → watchdog 自动还原，不留残色。

## 原理

两层解耦：

1. **信号层**（`bin/glow.sh`）— agent hooks 调一个 shell 脚本，往本窗口 pty 写 OSC 11「信号色」。四种高饱和特定亮度的颜色，普通暗色主题永远撞不上。没有 shader 也能用（退化成四种静态色）。纯 shell，零 token，无轮询——唯一的常驻进程是每个活跃窗口一个沉睡的 watchdog。
2. **特效层**（`shaders/astra-glow.glsl`）— Ghostty custom shader 从窗口四角采样背景色，按通道比例识别信号，只在背景像素上渲染对应的 60fps 特效。文字由色距蒙版保护。非信号色完全直通。

精髓：**背景颜色本身就是 shell 世界和 GPU 世界之间的通信信道**。不要 socket、不要文件、不要 daemon。

## 支持的 agent

- **Claude Code** — 完整四态，走 `~/.claude/settings.json` hooks
- **Codex CLI** — 同样四态，走 `~/.codex/hooks.json`（`UserPromptSubmit` / `Stop` / `PermissionRequest` / `PostToolUse`）
- 其他任何能在生命周期事件跑命令的 agent：调 `glow.sh run|done|attn|error|resume|end` 即可

## 安装

```bash
cd ~/Code/astra-glow
./install.sh            # ghostty + claude code + codex 全装, 幂等, 自动备份配置
```

装完重载 Ghostty（`cmd+shift+,`）或重启。agent 新开 session 生效。

立刻试效果：

```bash
bin/glow.sh demo 8      # 四态连播, 每态 8 秒
```

## 调参

- 催看阈值：`export GLOW_ATTN_SECS=300`（默认 600 秒）
- 特效密度/亮度/配色：改 `shaders/astra-glow.glsl`（单 `mainImage`，参数全内联），改完重载 Ghostty

## 踩坑实录（Ghostty shader 管线）

- Ghostty 的 GLSL→Metal 翻译链会**静默丢弃**编译不过的 shader，且 glslang 能编译 ≠ Ghostty 能跑。shader 必须保守：单 `mainImage`、辅助函数极少、无分支 one-hot 状态权重。
- `custom-shader-animation = always` 必须设。默认值在窗口失焦时暂停动画——而状态灯恰恰是给你没盯着的窗口看的。
- 检测门要宽（毛玻璃/半透明会衰减采样值），分类用通道**比例**（对亮度缩放免疫）。
- hook 进程通常没有 controlling tty。`glow.sh` 沿父进程链用 `lsof` 找第一个 stdio 挂 `/dev/ttys*` 的祖先——它既是目标 tty 也是存活锚点。

## License

MIT
