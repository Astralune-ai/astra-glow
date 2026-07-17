<div align="center">

# astra-glow

> *"Your terminal glows before you read a single word."*

![License](https://img.shields.io/badge/License-Source%20Available-blue)
![Shell](https://img.shields.io/badge/Shell-bash%203.2%2B-green)
![GPU](https://img.shields.io/badge/Effects-GLSL%2060fps-blueviolet)
![Ghostty](https://img.shields.io/badge/Terminal-Ghostty-orange)
![Tokens](https://img.shields.io/badge/AI%20token%20cost-0-brightgreen)

**[English](README.md) · [中文](README_CN.md)**

<br>

**Six agent tabs open — which one actually needs you?**

**Your agent finished ten minutes ago and you're still doom-scrolling?**

**It crashed an hour ago and nobody told you?**

<br>

### Ambient status lighting for AI coding agents.
### Aurora while it runs. Fireflies when it's done. A skull when it dies.

<br>

[**Quick Start**](#quick-start) · [**The Four States**](#the-four-states) · [**How It Works**](#how-it-works) · [**Tuning**](#tuning)

<br>

<img src="docs/demo.gif" alt="astra-glow — the four states, rendered live by the actual shader" width="690">

<sub>*Live render of the actual shader, cycling all four states.*</sub>

</div>

<br>

---

## Why this exists

Before: to know what an agent session was doing, you clicked into the tab, read the scrollback, figured out whether it was still running, finished, or waiting on an approval you missed — once per tab, many times per hour. Completed work sat unread; failed runs sat undiscovered.

With astra-glow, the window itself is the status line. One glance across your tabs: flowing aurora means working, green fireflies mean results are waiting, amber waves mean it wants you back, a skull means it went down. You never read a word to know where your attention should go.

## The Four States

| State | Trigger | Effect |
|---|---|---|
| 🌀 **Running** | you submit a prompt | dark aurora flowing across the background + stardust |
| 🟢 **Done, unread** | agent finishes the turn | emerald breathing + mist waves + drifting fireflies |
| 🟠 **Needs you** | unread for 10 min, or agent waits for approval | amber breathing + layered waves + rising particles |
| 💀 **Failed** | the turn errors out | a skull with pulsing red eyes, embers, vignette |

The light clears itself the moment it has done its job: **any keystroke in that window** (a reply, an Esc back to the session picker, even a scroll) counts as "seen" and restores your normal theme — detected via the tty's access time, no extra hooks needed. If the agent exits or crashes, a watchdog restores the color automatically — no stale glow left behind.

## Supported agents

| Agent | Wiring | States |
|---|---|---|
| **Claude Code** | `~/.claude/settings.json` hooks | all four |
| **Codex CLI** | `~/.codex/hooks.json` (`UserPromptSubmit` / `Stop` / `PermissionRequest` / `PostToolUse`) | all four |
| **Anything else** | call `glow.sh run\|done\|attn\|error\|resume\|end` on lifecycle events | all four |

## Quick Start

```bash
git clone https://github.com/Astralune-ai/astra-glow.git ~/Code/astra-glow
cd ~/Code/astra-glow
./install.sh          # ghostty + claude code + codex; idempotent; backs up configs
```

Reload Ghostty (`cmd+shift+,`) or restart it. New agent sessions light up automatically.

See it right now, in any terminal tab:

```bash
bin/glow.sh demo 8    # cycles all four states, 8s each
```

## How It Works

Two decoupled layers, and the background color itself is the IPC channel between them — no sockets, no files, no daemon:

1. **Signal layer** (`bin/glow.sh`) — agent hooks call one shell script that writes an OSC 11 "signal color" to the session's pty. Four saturated colors at a brightness normal dark themes never reach. Pure shell, zero AI tokens, zero polling; the only resident process is one sleeping watchdog per active window.
2. **Effect layer** (`shaders/astra-glow.glsl`) — a Ghostty custom shader samples the background from the window corners, classifies the signal by channel ratios, and renders the matching 60fps effect on background pixels only. Glyphs are protected by a color-distance mask. Non-signal backgrounds pass through untouched — and without the shader you still get four distinguishable flat colors.

The tty is discovered by walking the hook process's parent chain with `lsof` until an ancestor holds `/dev/ttys*` on stdio; that ancestor doubles as the liveness anchor the watchdog monitors.

## Tuning

| Knob | How |
|---|---|
| Unread → amber escalation delay | `export GLOW_ATTN_SECS=300` (default `600`) |
| Effect density / brightness / palette | edit `shaders/astra-glow.glsl` (single `mainImage`, parameters inline), reload Ghostty |
| Signal colors | top of `bin/glow.sh` + matching thresholds in the shader |

## Hard-Won Notes (Ghostty shader pipeline)

- Ghostty's GLSL→Metal translation chain **silently drops** shaders it can't compile — and passing `glslang` does not guarantee Ghostty accepts it. Keep shaders monolithic: one `mainImage`, minimal helpers, branchless one-hot state weights.
- `custom-shader-animation = always` is required. The default pauses animation for unfocused windows — and status lighting exists precisely for the windows you're not looking at.
- Detection thresholds must be loose (translucent, blurred backgrounds attenuate sampled values) and classification must use channel *ratios*, which brightness scaling can't break.
- Hook processes usually have no controlling tty; `/dev/tty` is a dead end. Walk the ancestry instead.

## Requirements & Terminal Compatibility

| Terminal | Signal colors (4 states) | GPU effects (aurora / fireflies / skull) |
|---|---|---|
| [Ghostty](https://ghostty.org) ≥ 1.2 | ✅ | ✅ full experience |
| iTerm2 / Kitty / WezTerm / Alacritty | ✅ (OSC 11 is universal) | — graceful degradation to flat status colors |

The two layers are decoupled by design: the signal layer needs only OSC 11 support, so on any modern terminal you still get four glanceable status colors. The animation layer rides on Ghostty's `custom-shader`, which has no equivalent elsewhere yet.

Also needed: `jq`, `lsof` (installer + engine), macOS, and an agent that fires lifecycle hooks.

**Installing via your agent works too** — tell Claude Code or Codex: *"install github.com/Astralune-ai/astra-glow"* and it will follow this README end to end. The installer is idempotent and backs up every config it touches.

## License

Astra Source Available License. Free for personal use and learning. Commercial use requires a separate license. See [LICENSE](LICENSE).

---

<div align="center">

**Stop checking on your agents. Let the light come to you.**

![astra-glow](https://img.shields.io/badge/astra--glow-ambient%20agent%20status-black?style=for-the-badge)

Powered by [**Astralune**](https://github.com/Astralune-ai)

</div>
