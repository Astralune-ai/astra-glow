#!/bin/bash
# glow-flow — 灯条 + 背景 状态对账引擎（事件驱动 + 自愈）
#
# 两件事, 都以状态文件 ~/.astra/glow/<tty>/state 为唯一真源:
#   1) OSC 4 灯条: statusline.sh 用索引色 17..30 打一条静态 dither 条,
#      本 daemon 按状态重定义这些索引的颜色。
#   2) OSC 11 背景: glow.sh 只在 hook 那一刻写一次背景, 一旦那次写入丢了/
#      被打断/hook 顺序乱, 背景就永久卡旧色。本 daemon 每检测到状态变化,
#      顺手把 OSC 11 背景也重贴一遍 → 背景 ≤5s 必收敛到当前状态色 (自愈)。
#
# ⚠️ 架构教训 (2026-07-22): xterm.js/Orca 每收一批 OSC 4 就重建颜色缓存+整屏
# 重绘, 单次 ≈4% CPU——「持续流动」(全员 8Hz) 曾把 Orca 烧到 100%+。所以严格
# 事件驱动: 稳态零写入; 仅 attn/error 入场爆 ~5s 4Hz 脉冲抓眼球, 再冻结。
# 已处理状态记在 <state_dir>/flowed, glow.sh 改 state → mark != state → 重贴。
#
# 用法: LaunchAgent com.asher.glow-flow (KeepAlive); 手动: nohup glow-flow.sh &

GLOW_ROOT="$HOME/.astra/glow"
BASE=17   # 起始调色板索引 (17..30 共 14 格, 与 statusline.sh 对齐)
N=14
FPS=4     # 仅脉冲帧率; 稳态零写入

while :; do
  # ── 每 5s 刷一次 pane 清单: 有状态 + tty 可写 + 锚点进程活着 ──
  panes=""
  for d in "$GLOW_ROOT"/*/; do
    [ -f "$d/state" ] || continue
    ttyname=$(basename "$d")
    [ -w "/dev/$ttyname" ] || continue
    a=$(cat "$d/anchor" 2>/dev/null)
    [ -n "$a" ] && kill -0 "$a" 2>/dev/null || continue
    panes="$panes $ttyname"
  done
  if [ -z "$panes" ]; then
    sleep 5
    continue
  fi

  # ── 单 awk 进程跑一个 5s 窗口 (20 帧 tick), 按需写入 ──
  awk -v panes="$panes" -v root="$GLOW_ROOT" -v base="$BASE" -v n="$N" \
      -v fps="$FPS" -v T0="$(date +%s)" '
  # 灯条一帧 (OSC 4 重定义索引 base..base+n-1)
  function bar(dev, r, g, b, t, sp,   i, v, out) {
    out = ""
    for (i = 0; i < n; i++) {
      v = 0.28 + 0.72*(0.5 + 0.5*sin(i*0.85 - t*sp))
      out = out sprintf("\033]4;%d;rgb:%02x/%02x/%02x\007",
                        base+i, int(r*v), int(g*v), int(b*v))
    }
    printf "%s", out > dev; fflush(dev); close(dev)
  }
  # 背景一次 (OSC 11 = 状态信号色, 与 glow.sh 的深色一致)
  function bg(dev, hex) {
    printf "\033]11;%s\007", hex > dev; fflush(dev); close(dev)
  }
  BEGIN{
    m = split(panes, P, " ")
    dt = 1.0/fps
    for (f = 0; f < 5*fps; f++) {
      t = T0 % 100000 + f*dt
      for (p = 1; p <= m; p++) {
        sd = root "/" P[p]
        sf = sd "/state"; state = ""
        if ((getline state < sf) < 0) { close(sf); continue }
        close(sf)
        # 灯条亮色(r,g,b) + 背景深色(bghex), 逐态
        if      (state=="run")   { r=77;  g=159; b=255; sp=2.6; bghex="#123c66" }
        else if (state=="done")  { r=52;  g=211; b=153; sp=1.4; bghex="#10663a" }
        else if (state=="attn")  { r=255; g=176; b=32;  sp=3.4; bghex="#654310" }
        else if (state=="error") { r=255; g=77;  b=77;  sp=4.5; bghex="#66101a" }
        else if (state=="seen")  { r=180; g=151; b=207; sp=0.8; bghex="#46156b" }
        else continue
        mf = sd "/flowed"; mark = ""
        if ((getline mark < mf) < 0) mark = ""
        close(mf)
        dev = "/dev/" P[p]
        pulsing = (state=="attn" || state=="error")
        if (mark != state) {
          # ── 状态变化: 背景 + 灯条各贴一次, 立即落 mark (防重写) ──
          bg(dev, bghex)
          bar(dev, r, g, b, t, sp)
          print state > mf; close(mf)
          if (pulsing) pulseEnd[P[p]] = t + 5   # 入场脉冲 5s (内存驱动)
        } else if (pulsing && (P[p] in pulseEnd) && t < pulseEnd[P[p]]) {
          # ── 脉冲窗口内: 只刷灯条制造流动, 背景已贴好不动 ──
          bar(dev, r, g, b, t, sp)
        }
      }
      system("sleep " dt)
    }
  }' 2>/dev/null
done
