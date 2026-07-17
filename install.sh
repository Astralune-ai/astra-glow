#!/bin/bash
# ============================================================
# astra-glow 安装器 (幂等, 可重复跑)
#
#   ./install.sh              # 装全部 (ghostty + claude + codex)
#   ./install.sh ghostty      # 只装 Ghostty shader 配置
#   ./install.sh claude       # 只装 Claude Code hooks
#   ./install.sh codex        # 只装 Codex hooks
#
# 改任何组件的配置前都会先备份 (.bak-astra-glow)。
# 装完: Ghostty 按 cmd+shift+, 重载 (或重启); agent 新 session 生效。
# ============================================================
set -e

REPO="$(cd "$(dirname "$0")" && pwd)"
GLOW="$REPO/bin/glow.sh"
SHADER="$REPO/shaders/astra-glow.glsl"
TARGET="${1:-all}"

need() { command -v "$1" >/dev/null || { echo "缺依赖: $1"; exit 1; }; }
need jq

hook_json() {
  # $1=verb → 一条 hook 定义
  jq -n --arg cmd "$GLOW $1" '{type:"command", command:$cmd, timeout:5}'
}

install_ghostty() {
  local cfg="$HOME/.config/ghostty/config"
  [ -f "$cfg" ] || { echo "跳过 ghostty: 找不到 $cfg"; return; }
  if grep -q "astra-glow.glsl" "$cfg"; then
    echo "ghostty: 已配置 ✓"
  else
    cp "$cfg" "$cfg.bak-astra-glow"
    # 清掉旧版 cc-glow 配置行
    grep -vE '^custom-shader( |-animation)|shaders/cc-glow' "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"
    cat >> "$cfg" <<EOF

# ─── astra-glow 状态特效 (由 install.sh 写入) ────────────
custom-shader = $SHADER
custom-shader-animation = always
EOF
    echo "ghostty: 已写入 custom-shader → 按 cmd+shift+, 重载或重启 Ghostty"
  fi
}

install_claude() {
  local s="$HOME/.claude/settings.json"
  [ -f "$s" ] || { echo "跳过 claude: 找不到 $s"; return; }
  if jq -e '.hooks | tostring | contains("astra-glow")' "$s" >/dev/null 2>&1; then
    echo "claude: 已配置 ✓"; return
  fi
  cp "$s" "$s.bak-astra-glow"
  jq --arg g "$GLOW" '
    def glow(v): {type:"command", command:($g + " " + v), timeout:5, async:true};
    def strip: if . == null then [] else
      [ .[] | .hooks = [ .hooks[] | select(.command | test("cc-glow|astra-glow") | not) ]
            | select(.hooks | length > 0) ] end;
    .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit | strip) + [{hooks:[glow("run")]}])
    | .hooks.SessionEnd     = ((.hooks.SessionEnd     | strip) + [{hooks:[glow("end")]}])
    | .hooks.Stop           = ((.hooks.Stop           | strip) + [{hooks:[glow("done")]}])
    | .hooks.StopFailure    = ((.hooks.StopFailure    | strip) + [{hooks:[glow("error")]}])
    | .hooks.Notification   = ((.hooks.Notification   | strip) + [{hooks:[glow("attn")]}])
    | .hooks.PostToolUse    = ((.hooks.PostToolUse    | strip) + [{hooks:[glow("resume")]}])
  ' "$s" > "$s.tmp" && jq empty "$s.tmp" && mv "$s.tmp" "$s"
  echo "claude: hooks 已接入 (新 session 生效)"
}

install_codex() {
  local h="$HOME/.codex/hooks.json"
  [ -d "$HOME/.codex" ] || { echo "跳过 codex: 找不到 ~/.codex"; return; }
  [ -f "$h" ] || echo '{"hooks":{}}' > "$h"
  if jq -e '.hooks | tostring | contains("astra-glow")' "$h" >/dev/null 2>&1; then
    echo "codex: 已配置 ✓"; return
  fi
  cp "$h" "$h.bak-astra-glow"
  # Codex 的 hook 事件名: UserPromptSubmit/Stop/PermissionRequest/PostToolUse
  jq --arg g "$GLOW" '
    def glow(v): {type:"command", command:($g + " " + v), timeout:5};
    def strip: if . == null then [] else
      [ .[] | .hooks = [ .hooks[] | select(.command | test("cc-glow|astra-glow") | not) ]
            | select(.hooks | length > 0) ] end;
    .hooks.UserPromptSubmit  = ((.hooks.UserPromptSubmit  | strip) + [{hooks:[glow("run")]}])
    | .hooks.Stop              = ((.hooks.Stop              | strip) + [{hooks:[glow("done")]}])
    | .hooks.PermissionRequest = ((.hooks.PermissionRequest | strip) + [{hooks:[glow("attn")]}])
    | .hooks.PostToolUse       = ((.hooks.PostToolUse       | strip) + [{hooks:[glow("resume")]}])
  ' "$h" > "$h.tmp" && jq empty "$h.tmp" && mv "$h.tmp" "$h"
  echo "codex: hooks 已接入 (新 session 生效)"
}

case "$TARGET" in
  all)     install_ghostty; install_claude; install_codex ;;
  ghostty) install_ghostty ;;
  claude)  install_claude ;;
  codex)   install_codex ;;
  *) echo "usage: install.sh [all|ghostty|claude|codex]"; exit 1 ;;
esac
echo "── astra-glow 安装完成 ──"
