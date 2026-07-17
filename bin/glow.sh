#!/bin/bash
# ============================================================
# astra-glow — 终端 AI Agent 状态呼吸灯 (Ghostty)
#
# 由 AI agent 的 hooks 驱动 (Claude Code / Codex / 任何能在
# 状态变化时调一条命令的 agent)。往本窗口的 pty 写 OSC 信号色,
# Ghostty custom-shader 检测信号色后渲染 60fps 特效:
#
#   run    正在跑     蓝 #123c66 → 极光流彩 + 星尘
#   done   完成待看   绿 #10663a → 翡翠呼吸 + 雾浪 + 萤火虫
#   attn   等人回来   琥珀 #654310 → 琥珀呼吸 + 波浪 + 粒子
#   error  翻车       红 #66101a → 骷髅头 + 红瞳 + 余烬
#
# 状态机:
#   run    (UserPromptSubmit)   清场 → 蓝
#   done   (Stop)               清场 → 绿; GLOW_ATTN_SECS 后自动升级琥珀
#   attn   (Notification/PermissionRequest) 清场 → 琥珀
#   error  (StopFailure)        清场 → 红
#   resume (PostToolUse)        仅当 attn 态 → 回到蓝 (授权通过继续跑)
#   end    (SessionEnd)         清场 → 还原
#
# 每个状态挂一个 watchdog: agent 进程消失 → 自动还原颜色并清场,
# 所以没有 SessionEnd hook 的 agent (如 Codex) 或 crash 也不留残色。
#
# 纯 shell + printf, 零 AI token 成本。bash 3.2 兼容。
# 项目: ~/Code/astra-glow  设计文档: docs/design.md
# ============================================================

GLOW_ROOT="$HOME/.astra/glow"
ATTN_SECS="${GLOW_ATTN_SECS:-${CC_GLOW_ATTN_SECS:-600}}"

# ── 四态信号色 (高饱和+亮度0.40, 普通暗色主题不会撞) ──
# 没加载 shader 时退化为四种静态色, 依然可辨
RUN_COLOR="#123c66"
DONE_COLOR="#10663a"
ATTN_COLOR="#654310"
ERROR_COLOR="#66101a"

VERB="$1"

# ── OSC 写入 ──
set_bg()    { printf '\033]11;%s\007' "$1" >> "$2" 2>/dev/null; }
reset_bg()  { printf '\033]111\007'        >> "$1" 2>/dev/null; }
set_title() { printf '\033]0;%s\007'  "$1" >> "$2" 2>/dev/null; }

anchor_gone() { ! kill -0 "$1" 2>/dev/null; }

# tty 设备的 atime 在用户敲键时更新 (w 的 idle 就靠它) → 天然的「已读」信号
tty_atime() { stat -f %a "$1" 2>/dev/null || stat -c %X "$1" 2>/dev/null || echo 0; }

# ============================================================
# watchdog (后台进程): 盯 agent 存活 + done→attn 升级
# ============================================================
if [ "$VERB" = "_watch" ]; then
  # $2=ttydev $3=anchor_pid $4=state_dir $5=mode(done|plain)
  TTYDEV="$2"; ANCHOR="$3"; SDIR="$4"; MODE="$5"
  elapsed=0
  BASE=$(cat "$SDIR/atime0" 2>/dev/null)
  while ! anchor_gone "$ANCHOR"; do
    sleep 5
    elapsed=$((elapsed + 5))
    # 自己已不是在册 watchdog → 退位 (新状态动词已接管)
    [ "$(cat "$SDIR/watch.pid" 2>/dev/null)" = "$$" ] || exit 0
    # 「敲键即已读」: done/attn/error 态下用户在本窗口敲了任何键
    # (回主屏的 Esc/方向键/滚动都算) → 灯的使命完成, 熄回原色。
    # 状态记成 seen 而非删目录: 若 agent 还在跑 (权限确认场景),
    # 授权通过后 PostToolUse 的 resume 靠它恢复运行蓝
    if [ -n "$BASE" ] && [ "$(tty_atime "$TTYDEV")" -gt "$BASE" ] 2>/dev/null; then
      echo "seen" > "$SDIR/state"
      rm -f "$SDIR/watch.pid" "$SDIR/atime0"
      reset_bg "$TTYDEV"
      exit 0
    fi
    if [ "$MODE" = "done" ] && [ "$elapsed" -ge "$ATTN_SECS" ]; then
      if [ "$(cat "$SDIR/state" 2>/dev/null)" = "done" ]; then
        echo "attn" > "$SDIR/state"
        set_bg "$ATTN_COLOR" "$TTYDEV"
        set_title "🔴 等你回来" "$TTYDEV"
      fi
      MODE="plain"
    fi
  done
  # agent 没了: 还原颜色, 清场
  reset_bg "$TTYDEV"
  rm -rf "$SDIR"
  exit 0
fi

# ============================================================
# 公共动词
# ============================================================

# ── tty + 锚点发现: 沿 PPID 链找第一个 stdio 挂 /dev/ttys* 的祖先 ──
# (hook 进程通常没有 controlling tty, 不能用 /dev/tty)
discover() {
  local pid=$$ i n
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    [ -z "$pid" ] && return 1
    [ "$pid" -le 1 ] && return 1
    n=$(lsof -a -p "$pid" -d 0,1,2 -Fn 2>/dev/null | grep -m1 '^n/dev/ttys' | cut -c2-)
    if [ -n "$n" ]; then
      FOUND_TTY="$n"; FOUND_ANCHOR="$pid"; return 0
    fi
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
  done
  return 1
}

# ── 状态目录: 按 tty 键控 (一个窗口=一个 tty=一盏灯) ──
init_state() {
  discover || exit 0
  TTYDEV="$FOUND_TTY"; ANCHOR="$FOUND_ANCHOR"
  SDIR="$GLOW_ROOT/$(basename "$TTYDEV")"
  mkdir -p "$SDIR"
  echo "$TTYDEV" > "$SDIR/tty"; echo "$ANCHOR" > "$SDIR/anchor"
}

# ── 清场: 杀掉本窗口的 watchdog (校验 command 防 pid 复用误杀) ──
kill_jobs() {
  local p
  p=$(cat "$SDIR/watch.pid" 2>/dev/null)
  if [ -n "$p" ] && ps -o command= -p "$p" 2>/dev/null | grep -q glow; then
    kill "$p" 2>/dev/null
  fi
  rm -f "$SDIR/watch.pid"
}

spawn_watch() {
  # $1=mode
  nohup "$0" _watch "$TTYDEV" "$ANCHOR" "$SDIR" "$1" </dev/null >/dev/null 2>&1 &
  echo $! > "$SDIR/watch.pid"
  disown 2>/dev/null
}

case "$VERB" in
  run)
    init_state
    kill_jobs
    echo "run" > "$SDIR/state"
    rm -f "$SDIR/atime0"   # 运行态不做「敲键即已读」— 打字不该熄掉极光
    set_bg "$RUN_COLOR" "$TTYDEV"
    spawn_watch plain
    # 顺手 GC 超过 7 天的孤儿状态目录
    find "$GLOW_ROOT" -maxdepth 1 -mindepth 1 -type d -mtime +7 -exec rm -rf {} + 2>/dev/null
    ;;
  done)
    init_state
    kill_jobs
    echo "done" > "$SDIR/state"
    tty_atime "$TTYDEV" > "$SDIR/atime0"
    set_bg "$DONE_COLOR" "$TTYDEV"
    set_title "✅ 完成待看" "$TTYDEV"
    spawn_watch done
    ;;
  attn)
    # Claude Code 的 Notification 事件混着两种通知:
    #   权限请求 ("Claude needs your permission ...") → 真·等人, 该变琥珀
    #   闲置提醒 ("Claude is waiting for your input", Stop 后 ~60s 就发)
    #     → 忽略! 否则完成绿一分钟就被刷黄; 10 分钟催看由 watchdog 升级
    # (Codex 走 PermissionRequest 事件, 无此歧义, message 不匹配会直接放行)
    if [ ! -t 0 ]; then
      MSG=$(cat 2>/dev/null | jq -r '.message // empty' 2>/dev/null)
      case "$MSG" in
        *[Ww]aiting*) exit 0 ;;
      esac
    fi
    init_state
    kill_jobs
    echo "attn" > "$SDIR/state"
    tty_atime "$TTYDEV" > "$SDIR/atime0"
    set_bg "$ATTN_COLOR" "$TTYDEV"
    set_title "🔔 等你回应" "$TTYDEV"
    spawn_watch plain
    ;;
  error)
    init_state
    kill_jobs
    echo "error" > "$SDIR/state"
    tty_atime "$TTYDEV" > "$SDIR/atime0"
    set_bg "$ERROR_COLOR" "$TTYDEV"
    set_title "❌ 翻车了" "$TTYDEV"
    spawn_watch plain
    ;;
  resume)
    # PostToolUse 高频调用: attn (等授权) 或 seen (已读熄灯但 agent 还在跑)
    # 才需要动作 → 回到运行蓝; 其余状态秒退
    init_state
    case "$(cat "$SDIR/state" 2>/dev/null)" in attn|seen) ;; *) exit 0 ;; esac
    kill_jobs
    echo "run" > "$SDIR/state"
    rm -f "$SDIR/atime0"
    set_bg "$RUN_COLOR" "$TTYDEV"
    spawn_watch plain
    ;;
  end)
    init_state
    kill_jobs
    reset_bg "$TTYDEV"
    rm -rf "$SDIR"
    ;;
  demo)
    # 手动演示: 在当前终端连播四态 (需要真 tty)
    init_state
    for c in "$RUN_COLOR" "$DONE_COLOR" "$ATTN_COLOR" "$ERROR_COLOR"; do
      set_bg "$c" "$TTYDEV"; sleep "${2:-8}"
    done
    reset_bg "$TTYDEV"
    ;;
  *)
    echo "usage: glow.sh {run|done|attn|error|resume|end|demo [secs]}" >&2
    exit 1
    ;;
esac

exit 0
