<div align="center">

# astra-glow

**Your terminal tells you what your AI agent is doing — before you read a single word.**

Ambient status lighting for AI coding agents in [Ghostty](https://ghostty.org): GPU-rendered aurora, fireflies, amber waves, and a skull — driven by agent lifecycle hooks, at zero token cost.

[中文文档](README_CN.md)

</div>

---

## What it does

Glance at your terminal tabs and instantly know the state of every agent session:

| State | Trigger | Effect |
|---|---|---|
| 🌀 **Running** | you submit a prompt | dark aurora flowing across the background + stardust |
| 🟢 **Done, unread** | agent finishes | emerald breathing + mist waves + drifting fireflies |
| 🟠 **Needs you** | 10 min unread, or agent waits for approval | amber breathing + layered waves + rising particles |
| 💀 **Failed** | agent errors out | a skull with pulsing red eyes, embers, vignette |

Reply in the window → everything resets to your normal theme. Agent exits or crashes → a watchdog restores the color automatically.

## How it works

Two decoupled layers:

1. **Signal layer** (`bin/glow.sh`) — agent hooks call one shell script that writes an OSC 11 "signal color" to the session's pty. Four saturated colors at a brightness normal dark themes never reach. Works even without the shader (you just get flat colors instead of animation). Pure shell, zero AI tokens, zero background polling — the only resident process is one sleeping watchdog per active window.
2. **Effect layer** (`shaders/astra-glow.glsl`) — a Ghostty custom shader samples the background color from the window corners, classifies the signal by channel ratios, and renders the matching 60fps effect on background pixels only. Text is protected by a color-distance mask. Non-signal backgrounds pass through untouched.

The clever bit: the *background color itself is the IPC channel* between the shell world and the GPU world. No sockets, no files, no daemon.

## Supported agents

- **Claude Code** — full 4-state mapping via `~/.claude/settings.json` hooks
- **Codex CLI** — same mapping via `~/.codex/hooks.json` (`UserPromptSubmit` / `Stop` / `PermissionRequest` / `PostToolUse`)
- Anything else that can run a command on lifecycle events: call `glow.sh run|done|attn|error|resume|end`

## Install

```bash
git clone <repo> ~/Code/astra-glow
cd ~/Code/astra-glow
./install.sh            # ghostty + claude code + codex, idempotent, backs up configs
```

Then reload Ghostty (`cmd+shift+,`) or restart it. New agent sessions pick up the hooks.

Try it immediately in any terminal tab:

```bash
bin/glow.sh demo 8      # cycles all four states, 8s each
```

## Tuning

- Unread-escalation delay: `export GLOW_ATTN_SECS=300` (default 600)
- Effect density/brightness/colors: edit `shaders/astra-glow.glsl` (single `mainImage`, parameters inline), then reload Ghostty

## Hard-won notes (Ghostty shader pipeline)

- Ghostty's GLSL→Metal translation chain silently drops shaders it can't compile — and compiling clean under `glslang` does **not** guarantee Ghostty accepts it. Keep shaders monolithic: one `mainImage`, minimal helper functions, branchless one-hot state weights.
- `custom-shader-animation = always` is required. The default pauses animation for unfocused windows — and status lighting exists precisely for the windows you're not looking at.
- Detection thresholds must be loose (translucent/blurred backgrounds attenuate sampled values) and classification must use channel *ratios*, which are immune to brightness scaling.
- Hook processes usually have no controlling tty. `glow.sh` walks the parent chain and finds the first ancestor with `/dev/ttys*` on stdio via `lsof` — that ancestor is both the target tty and the liveness anchor.

## License

MIT
