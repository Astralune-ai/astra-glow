// ============================================================
// astra-glow-grid.glsl — tmux 宫格版:每个 pane 各自一盏灯
//
// 与 astra-glow.glsl 同款五态特效，区别只在「采样 + 坐标」:
//   · 原版: 四角采样一个全局信号色，效果铺满整个 surface。
//   · 本版: 把 surface 按 COLS×ROWS 切成格，每格独立采样自己的信号色，
//           效果用「格内本地坐标 puv(0..1)」渲染 → 每格显示完整居中效果，
//           跟原生 Ghostty 分屏每格一盏灯一模一样。
//
// 信号色由 glow.sh(tmux 模式)用 `tmux select-pane -P bg=<hex>` 设到各 pane:
//   run 蓝#123c66 / done 绿#10663a / attn 琥珀#654310 / err 红#66101a / seen 紫#46156b
//
// COLS/ROWS 由启动器(ghostty_grid.sh)按实际宫格 sed 写入。默认 4×2。
// 写法沿用原版保守约束(单 mainImage + 唯一辅助函数 hash21, 全内联)。
// ============================================================

const float COLS = 4.0;   // @GRID_COLS@
const float ROWS = 2.0;   // @GRID_ROWS@

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec4 tex = texture(iChannel0, uv);
    float t = iTime;

    // ── 定位当前像素所在的格 + 格内本地坐标 puv(0..1) ──
    vec2 grid = vec2(COLS, ROWS);
    vec2 cell = floor(uv * grid);
    vec2 cellOrigin = cell / grid;
    vec2 cellSize = 1.0 / grid;
    vec2 puv = fract(uv * grid);
    float aspect = (iResolution.x * ROWS) / (iResolution.y * COLS);  // 单格宽高比

    // ── 鲁棒采样本格信号色: 格内 16 点取最像信号色的一点(躲开文字污染) ──
    vec3 bg = vec3(0.0);
    float best = -1.0;
    for (int i = 0; i < 16; i++) {
        float fi = float(i);
        vec2 sp2 = vec2(mod(fi, 4.0), floor(fi / 4.0)) / 3.0;         // 0..1 网格
        vec2 q = cellOrigin + cellSize * (0.12 + 0.76 * sp2);
        vec3 c = texture(iChannel0, q).rgb;
        float mx = max(c.r, max(c.g, c.b));
        float mn = min(c.r, min(c.g, c.b));
        float s = (mx - mn) / max(mx, 1e-4);
        float score = smoothstep(0.26, 0.32, mx) * smoothstep(0.45, 0.60, s);
        if (score > best) { best = score; bg = c; }
    }
    if (best < 0.01) { fragColor = tex; return; }                    // 本格非信号态 → 直通

    float maxc = max(bg.r, max(bg.g, bg.b));
    float gate = best;

    // ── one-hot 状态权重 (通道比例, 对亮度缩放免疫) ──
    vec3 nb = bg / max(maxc, 1e-4);
    float warm      = step(nb.g, nb.r) * step(nb.b, nb.r);
    float amberness = smoothstep(0.15, 0.25, nb.g - nb.b);
    float wAmber = warm * amberness;
    float wRed   = warm * (1.0 - amberness);
    float wGreen = (1.0 - warm) * step(nb.r, nb.g) * step(nb.b, nb.g);
    float coldB  = clamp(1.0 - warm - wGreen, 0.0, 1.0);
    float violetness = smoothstep(0.15, 0.30, nb.r - nb.g);
    float wViolet = coldB * violetness;
    float wBlue   = coldB * (1.0 - violetness);

    // ════ run: 极光流彩 (格内坐标) ════
    float w1 = sin(puv.x * 3.0 + t * 0.50 + sin(puv.y * 4.0 + t * 0.30) * 0.8);
    float w2 = sin(puv.y * 5.0 - t * 0.40 + w1);
    float hue = t * 0.06 + puv.x * 0.35 - puv.y * 0.22 + w1 * 0.12 + w2 * 0.08;
    vec3 effRun = vec3(0.105) + vec3(0.080) * cos(6.28318 * (hue + vec3(0.0, 0.33, 0.67)));
    effRun *= 1.0 + 0.22 * sin(puv.x * 6.0 + t * 0.7 + w2);

    // ════ done: 翡翠呼吸 + 雾浪 ════
    vec3 effDone = vec3(0.045, 0.150, 0.095) * (1.0 + 0.16 * sin(t * 1.1 + puv.y * 2.0));
    float mist = smoothstep(0.34 + 0.05 * sin(puv.x * 4.0 + t * 0.6), 0.0, puv.y) * 0.55
               + smoothstep(0.16 + 0.04 * sin(puv.x * 7.0 - t * 0.9), 0.0, puv.y) * 0.55
               + smoothstep(0.10 + 0.03 * sin(puv.x * 9.0 + t * 0.8), 0.0, 1.0 - puv.y) * 0.35;
    effDone += vec3(0.020, 0.105, 0.060) * mist;

    // ════ attn: 琥珀呼吸 + 层叠波浪 ════
    vec3 effAttn = bg * (1.0 + 0.10 * (0.5 + 0.5 * sin(t * 1.8)));
    float eb = puv.y;
    float et = 1.0 - puv.y;
    float lineB1 = 0.10 + 0.030 * sin(puv.x * 9.0  + t * 1.6)
                        + 0.018 * sin(puv.x * 23.0 - t * 2.7);
    float lineB2 = 0.16 + 0.040 * sin(puv.x * 6.0  - t * 1.1)
                        + 0.020 * sin(puv.x * 17.0 + t * 2.2);
    float lineT  = 0.08 + 0.025 * sin(puv.x * 11.0 - t * 1.9);
    float waves = smoothstep(lineB1, 0.0, eb) * 0.8
                + smoothstep(lineB2, 0.0, eb) * 0.4
                + smoothstep(lineT,  0.0, et) * 0.5;
    effAttn = mix(effAttn, vec3(0.55, 0.28, 0.05) + vec3(1.0, 0.60, 0.16) * 0.4,
                  clamp(waves, 0.0, 1.0) * 0.45);

    // ════ error: 骷髅头 (格内坐标 + 单格宽高比) ════
    // puv.y 相对纹理是翻的 → 骷髅这种强上下不对称的图形要把 y 翻正(颅骨朝上)
    vec3 effErr = vec3(0.130, 0.030, 0.040) * (1.0 + 0.10 * sin(t * 2.1));
    vec2 sp = vec2(puv.x, 1.0 - puv.y) - vec2(0.5, 0.54);
    sp.x *= aspect;
    sp /= 0.34 * (1.0 + 0.02 * sin(t * 2.1));
    vec2 cp = sp - vec2(0.0, 0.20);
    float cran = (length(cp / vec2(0.80, 0.74)) - 1.0) * 0.74;
    vec2 jq = abs(sp - vec2(0.0, -0.50)) - vec2(0.30, 0.26) + 0.16;
    float jaw = length(max(jq, 0.0)) + min(max(jq.x, jq.y), 0.0) - 0.16;
    float head = min(cran, jaw);
    float bodyM = smoothstep(0.03, -0.03, head);
    vec2 ep = vec2(abs(sp.x), sp.y) - vec2(0.30, 0.12);
    float eye = (length(ep / vec2(0.19, 0.23)) - 1.0) * 0.19;
    vec2 np2 = sp - vec2(0.0, -0.26);
    float nose = (length(np2 / vec2(0.10, 0.16)) - 1.0) * 0.10;
    float cuts = smoothstep(0.02, -0.02, eye) + smoothstep(0.02, -0.02, nose);
    float inJaw = smoothstep(0.02, -0.02, jaw) * (1.0 - smoothstep(-0.34, -0.28, sp.y));
    float stripes = smoothstep(0.55, 0.90, cos(sp.x * 26.0)) * inJaw;
    vec3 bone = vec3(0.40, 0.34, 0.32) * (0.90 + 0.18 * sp.y);
    effErr = mix(effErr, bone, bodyM * 0.90);
    effErr = mix(effErr, vec3(0.05, 0.010, 0.015), clamp(cuts, 0.0, 1.0) * bodyM);
    effErr = mix(effErr, vec3(0.08, 0.020, 0.030), stripes * 0.85);
    vec2 pp = vec2(abs(sp.x), sp.y) - vec2(0.30, 0.06);
    float pupil = smoothstep(0.11, 0.0, length(pp * vec2(1.0, 1.3)));
    effErr += vec3(0.95, 0.10, 0.08) * pupil * (0.55 + 0.45 * sin(t * 3.2)) * bodyM;
    float glowSk = exp(-max(head, 0.0) * 3.5) * (1.0 - bodyM);
    effErr += vec3(0.50, 0.08, 0.10) * glowSk * (0.6 + 0.4 * sin(t * 2.1));
    float vig = smoothstep(1.15, 0.35, length((puv - 0.5) * vec2(aspect, 1.0)));
    effErr *= 0.55 + 0.45 * vig;

    // ════ seen: 静谧紫罗兰夜灯 ════
    vec3 effSeen = vec3(0.100, 0.052, 0.165) * (1.0 + 0.10 * sin(t * 0.9 + puv.y * 1.5));
    float rim = smoothstep(0.45, 1.05, length((puv - 0.5) * vec2(aspect, 1.0)));
    effSeen += vec3(0.14, 0.08, 0.26) * rim * (0.55 + 0.30 * sin(t * 0.7));

    // ════ 粒子 (格内坐标, 参数按 one-hot 权重混合) ════
    float pSpeed = 0.25 * wBlue + 0.35 * wGreen + 1.00 * wAmber + 0.80 * wRed + 0.12 * wViolet;
    float pSize  = 0.05 * wBlue + 0.09 * wGreen + 0.10 * wAmber + 0.07 * wRed + 0.06 * wViolet;
    float pThr   = 0.90 * wBlue + 0.80 * wGreen + 0.75 * wAmber + 0.82 * wRed + 0.88 * wViolet;
    float pSeed  = 7.0  * wBlue + 3.0  * wGreen + 0.00 * wAmber + 11.0 * wRed + 21.0 * wViolet;
    vec3  pCol   = vec3(0.90, 0.95, 1.00) * 0.25 * wBlue
                 + vec3(0.45, 0.95, 0.55) * 0.45 * wGreen
                 + vec3(1.00, 0.60, 0.16) * 0.50 * wAmber
                 + vec3(1.00, 0.35, 0.10) * 0.40 * wRed
                 + vec3(0.72, 0.58, 1.00) * 0.30 * wViolet;
    float parts = 0.0;
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float scale = 12.0 + fi * 9.0;
        vec2 p = puv * scale * vec2(aspect, 1.0);
        p.y -= t * pSpeed * (0.6 + 0.35 * fi);
        p.x += sin(t * 0.6 + fi * 2.0 + puv.y * 4.0) * 0.3;
        vec2 id = floor(p);
        vec2 f  = fract(p) - 0.5;
        float rnd = hash21(id + fi * 17.0 + pSeed);
        if (rnd > pThr) {
            vec2 off = 0.30 * vec2(sin(t * (0.8 + rnd) + rnd * 6.28),
                                   cos(t * (0.5 + rnd * 0.7) + rnd * 12.6));
            float d  = length(f - off);
            float tw = 0.55 + 0.45 * sin(t * (1.5 + 2.5 * rnd) + rnd * 40.0);
            parts += smoothstep(pSize * (1.0 + rnd), 0.0, d) * tw * (0.35 + 0.25 * fi);
        }
    }

    // ── 合成: 状态效果 + 粒子, 文字蒙版保护 ──
    vec3 eff = effRun * wBlue + effDone * wGreen + effAttn * wAmber + effErr * wRed
             + effSeen * wViolet;
    eff += pCol * parts;
    float isBg = 1.0 - smoothstep(0.06, 0.18, distance(tex.rgb, bg));
    fragColor = vec4(mix(tex.rgb, eff, isBg * gate), tex.a);
}
