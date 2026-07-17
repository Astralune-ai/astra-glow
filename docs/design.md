# cc-glow · Claude Code 状态呼吸灯 设计文档

日期：2026-07-16 · 状态：已批准（Asher 拍板方案 A + 回复即已读 + 10 分钟阈值）

## 目标

让 Ghostty 里的 Claude Code session 用窗口颜色表达三态，不看文字就知道状态：

1. **运行中** — 背景暗色系彩虹缓慢流转（炫彩呼吸）
2. **完成未读** — 背景定格墨绿调
3. **完成且 10 分钟未理** — 琥珀色慢脉冲，抓注意力
4. （附送）**出错** — 暗红定格；**CC 等授权/回应** — 直接进琥珀脉冲

你在该 session 输入下一条 prompt、或 session 退出 → 还原 Kanagawa 原色。

## 方案

不改 Ghostty 源码。Claude Code hooks 驱动一个状态机脚本 `~/.claude/scripts/cc-glow.sh`，
往本 session 所在 tab 的 pty 写 OSC 转义序列：

- `OSC 11` 设背景色（毛玻璃半透明 + tabs 标题栏 → 整窗变调，即"整框状态灯"）
- `OSC 111` 还原配置默认背景色
- `OSC 0` 设标签标题 emoji（best-effort，CC 自己会刷标题，可能被盖）

## 关键工程决策

### tty 发现（实测定型）
hook 进程在 CC 下常无 controlling tty（`ps -o tty=` 给 `??`），不能用 `/dev/tty`。
定型做法：沿 PPID 链向上走（≤12 层），对每个祖先 `lsof -a -p PID -d 0,1,2 -Fn`
找第一个 stdio 挂着 `/dev/ttysNNN` 的进程 —— 该进程即锚点（claude 主进程），
其 tty 即目标。实测 2 跳命中。无 tty（SSH/headless）→ 静默退出。

### 状态目录与缓存
`~/.claude/glow/<session_id>/`（session_id 取自 hook stdin JSON；手动调用时退化为 tty 名）。
内含 `tty`、`anchor`（锚点 pid）、`state`、`anim.pid`、`timer.pid`。
tty/anchor 在 `run` 时发现一次并缓存，后续动词直接复用（省掉每次 lsof）。

### 动词表
| 动词 | 触发 hook | 行为 |
|---|---|---|
| `run` | UserPromptSubmit | 清场→还原→启动彩虹 animator（24 色×0.35s/帧） |
| `done` | Stop | 清场→定格墨绿→埋 600s 定时器（到点转琥珀脉冲） |
| `error` | StopFailure | 清场→定格暗红 |
| `attn` | Notification | 清场→琥珀脉冲 |
| `resume` | PostToolUse | 仅当 state==attn 时等价于 run（授权通过后回到运行态）；否则 <5ms 直接退出 |
| `end` | SessionEnd | 清场→OSC 111 还原→删状态目录 |

### 防僵尸三保险
1. animator/pulse/timer 每帧 `kill -0 <anchor>`，claude 主进程没了 → 还原并自杀
2. 往 tty 写失败（tab 关了）→ 自杀
3. kill 前校验 pid 的 command 含 cc-glow 才杀（防 pid 复用误杀）

### 配色（Kanagawa Wave 兼容，低亮度不伤可读性）
- 彩虹：HSL 色环 24 步，S≈42% L≈17%
- 墨绿定格：暗青绿；琥珀脉冲：4 色 ramp 往返；暗红：定格

## 改动面
- 新增 `~/.claude/scripts/cc-glow.sh`
- `~/.claude/settings.json`：新增 UserPromptSubmit/SessionEnd 两个 hook 组，
  Stop/StopFailure/Notification/PostToolUse 各追加一条（全部 async，timeout 5s）
- Ghostty 配置零改动；现有 notify.sh 通知链原样保留
- 零 AI token 成本（纯 shell 定时 + printf）

## Phase 2（2026-07-16 同日追加）：GPU 波浪+粒子特效

Asher 反馈 OSC 分级琥珀脉冲(0.5s/步)卡顿，要波浪/粒子。OSC 只能整片匀色，
遂上 Ghostty custom-shader（GLSL，60fps GPU 渲染）：

- **信号色机制**：attn 态改为定格高亮琥珀 `#654310`（亮度 0.40，彩虹最亮仅 0.24）。
  shader 从四角采样背景色（padding 区永远是纯背景），命中「暖色+高饱和+高亮度」
  才激活特效，其余状态直通零开销。彩虹会路过琥珀色相，靠亮度阈值消歧。
- **特效**：平滑正弦呼吸 + 上下边缘层叠波浪（上下对称，对纹理 y 翻转免疫）+
  三层视差上浮粒子（游移+闪烁）。文字像素用「与背景色距离」蒙版保护不被污染。
- **文件**：`~/.config/ghostty/shaders/cc-glow.glsl`；config 加
  `custom-shader` + `custom-shader-animation = true`
- **降级**：没加载 shader 时 attn = 静态琥珀，依然可辨
- 脚本侧删除 `_pulse` 循环（attn/_timer 直接定格信号色）；彩虹加密到 36 色×0.28s

## Phase 3（同日追加）：四态动画全部归 GPU

Asher 确认琥珀特效后拍板：run/done 也要 fancy 动画，error 要骷髅头。
架构再简化——OSC 层退化成纯「信号色」，shader 包办全部动画：

| 状态 | 信号色 | GPU 特效 |
|---|---|---|
| run | 蓝 `#123c66` | 暗色极光流彩（多层正弦 hue 场）+ 星尘 |
| done | 绿 `#10663a` | 翡翠呼吸 + 上下雾浪 + 上浮萤火虫 |
| attn | 琥珀 `#654310` | 琥珀呼吸 + 层叠波浪 + 上浮粒子（Phase 2 原效果） |
| error | 红 `#66101a` | SDF 骷髅头（颅骨+颌骨+眼窝+红瞳脉动+牙缝+外发光）+ 余烬 + 暗角 |

- 四信号色统一「高饱和 + 亮度 0.40」，先过亮度/饱和门再按主导通道分类
- 彩虹 OSC animator 删除——后台进程只剩 done→attn 的 600s 定时器
- 无 shader 降级：四种静态色仍可辨状态

### Phase 3.1 排障定稿（2026-07-17 验收通过）

首版 Phase 3（8 个函数拆分）在 Ghostty 的 GLSL→Metal 翻译链上编译失败被静默丢弃
（glslang 能过，Ghostty 不行；unified log 查不到 Ghostty 日志）。定稿三原则：

1. **保守写法**：单 mainImage + 唯一辅助函数 hash21，效果全内联，
   状态分类用无分支 one-hot 权重（粒子一趟共用，参数按权重混合）
2. **`custom-shader-animation = always`**：`true` 在窗口失焦/闲置时暂停动画，
   而状态灯正是给失焦窗口看的
3. **检测门宽松无上限**：`smoothstep(0.26,0.32,maxc) × smoothstep(0.45,0.60,sat)`，
   分类用通道比例——对毛玻璃/预乘造成的亮度衰减免疫

另修：状态目录从 session_id 改为按 tty 键控（session_id 会因 fork/上下文压缩
变化，多目录抢同一窗口导致颜色打架）。

## 测试
1. 直接对当前 session 的 tty 手动跑各动词，肉眼验证四态颜色 + 还原
2. 验证 animator 在锚点进程消失后自动还原退出
3. jq 校验 settings.json 合法；新 session 生效（hooks 会话启动时快照，当前已开 session 不回溯）
