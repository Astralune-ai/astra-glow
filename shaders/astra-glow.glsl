// ============================================================
// cc-glow.glsl — Claude Code 四态 GPU 特效 (v3.1 保守重写)
//
// 写法刻意贴着实测能跑的 Phase 2 版本: 单 mainImage + 唯一辅助
// 函数 hash21, 全部效果内联, 分类走无分支 one-hot 权重。
//
// 信号色 (cc-glow.sh 设置):
//   run  蓝  #123c66 → 极光流彩 + 星尘
//   done 绿  #10663a → 翡翠呼吸 + 雾浪 + 萤火虫
//   attn 琥珀 #654310 → 琥珀呼吸 + 波浪 + 粒子 (Phase 2 原效果)
//   err  红  #66101a → 骷髅头 + 红瞳 + 余烬
// 非信号色完全直通; 文字像素蒙版保护。
// ============================================================

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec4 tex = texture(iChannel0, uv);
    float aspect = iResolution.x / iResolution.y;
    float t = iTime;

    // ── 四角采样背景色 (padding 区永远是纯背景) ──
    vec2 px = 6.0 / iResolution.xy;
    vec3 bg = ( texture(iChannel0, px).rgb
              + texture(iChannel0, vec2(1.0 - px.x, px.y)).rgb
              + texture(iChannel0, vec2(px.x, 1.0 - px.y)).rgb
              + texture(iChannel0, 1.0 - px).rgb ) * 0.25;

    // ── 信号色门 (宽松: 兼容半透明/预乘造成的亮度衰减) ──
    float maxc = max(bg.r, max(bg.g, bg.b));
    float minc = min(bg.r, min(bg.g, bg.b));
    float sat  = (maxc - minc) / max(maxc, 1e-4);
    float gate = smoothstep(0.26, 0.32, maxc) * smoothstep(0.45, 0.60, sat);
    if (gate < 0.01) { fragColor = tex; return; }

    // ── one-hot 状态权重 (通道比例, 对亮度缩放免疫) ──
    vec3 nb = bg / max(maxc, 1e-4);
    float warm      = step(nb.g, nb.r) * step(nb.b, nb.r);
    float amberness = smoothstep(0.15, 0.25, nb.g - nb.b);
    float wAmber = warm * amberness;
    float wRed   = warm * (1.0 - amberness);
    float wGreen = (1.0 - warm) * step(nb.r, nb.g) * step(nb.b, nb.g);
    float wBlue  = clamp(1.0 - warm - wGreen, 0.0, 1.0);

    // ════ run: 极光流彩 ════
    float w1 = sin(uv.x * 3.0 + t * 0.50 + sin(uv.y * 4.0 + t * 0.30) * 0.8);
    float w2 = sin(uv.y * 5.0 - t * 0.40 + w1);
    float hue = t * 0.06 + uv.x * 0.35 - uv.y * 0.22 + w1 * 0.12 + w2 * 0.08;
    vec3 effRun = vec3(0.105) + vec3(0.080) * cos(6.28318 * (hue + vec3(0.0, 0.33, 0.67)));
    effRun *= 1.0 + 0.22 * sin(uv.x * 6.0 + t * 0.7 + w2);

    // ════ done: 翡翠呼吸 + 雾浪 ════
    vec3 effDone = vec3(0.045, 0.150, 0.095) * (1.0 + 0.16 * sin(t * 1.1 + uv.y * 2.0));
    float mist = smoothstep(0.34 + 0.05 * sin(uv.x * 4.0 + t * 0.6), 0.0, uv.y) * 0.55
               + smoothstep(0.16 + 0.04 * sin(uv.x * 7.0 - t * 0.9), 0.0, uv.y) * 0.55
               + smoothstep(0.10 + 0.03 * sin(uv.x * 9.0 + t * 0.8), 0.0, 1.0 - uv.y) * 0.35;
    effDone += vec3(0.020, 0.105, 0.060) * mist;

    // ════ attn: 琥珀呼吸 + 层叠波浪 (Phase 2 原效果) ════
    vec3 effAttn = bg * (1.0 + 0.10 * (0.5 + 0.5 * sin(t * 1.8)));
    float eb = uv.y;
    float et = 1.0 - uv.y;
    float lineB1 = 0.10 + 0.030 * sin(uv.x * 9.0  + t * 1.6)
                        + 0.018 * sin(uv.x * 23.0 - t * 2.7);
    float lineB2 = 0.16 + 0.040 * sin(uv.x * 6.0  - t * 1.1)
                        + 0.020 * sin(uv.x * 17.0 + t * 2.2);
    float lineT  = 0.08 + 0.025 * sin(uv.x * 11.0 - t * 1.9);
    float waves = smoothstep(lineB1, 0.0, eb) * 0.8
                + smoothstep(lineB2, 0.0, eb) * 0.4
                + smoothstep(lineT,  0.0, et) * 0.5;
    effAttn = mix(effAttn, vec3(0.55, 0.28, 0.05) + vec3(1.0, 0.60, 0.16) * 0.4,
                  clamp(waves, 0.0, 1.0) * 0.45);

    // ════ error: 骷髅头 ════
    vec3 effErr = vec3(0.130, 0.030, 0.040) * (1.0 + 0.10 * sin(t * 2.1));
    vec2 sp = uv - vec2(0.5, 0.54);
    sp.x *= aspect;
    sp /= 0.34 * (1.0 + 0.02 * sin(t * 2.1));
    vec2 cp = sp - vec2(0.0, 0.20);                               // 颅骨 (椭圆)
    float cran = (length(cp / vec2(0.80, 0.74)) - 1.0) * 0.74;
    vec2 jq = abs(sp - vec2(0.0, -0.50)) - vec2(0.30, 0.26) + 0.16; // 颌骨 (圆角盒)
    float jaw = length(max(jq, 0.0)) + min(max(jq.x, jq.y), 0.0) - 0.16;
    float head = min(cran, jaw);
    float body = smoothstep(0.03, -0.03, head);
    vec2 ep = vec2(abs(sp.x), sp.y) - vec2(0.30, 0.12);           // 眼窝 (x 镜像一次算两只)
    float eye = (length(ep / vec2(0.19, 0.23)) - 1.0) * 0.19;
    vec2 np2 = sp - vec2(0.0, -0.26);                             // 鼻腔
    float nose = (length(np2 / vec2(0.10, 0.16)) - 1.0) * 0.10;
    float cuts = smoothstep(0.02, -0.02, eye) + smoothstep(0.02, -0.02, nose);
    float inJaw = smoothstep(0.02, -0.02, jaw) * (1.0 - smoothstep(-0.34, -0.28, sp.y));
    float stripes = smoothstep(0.55, 0.90, cos(sp.x * 26.0)) * inJaw;  // 牙缝
    vec3 bone = vec3(0.40, 0.34, 0.32) * (0.90 + 0.18 * sp.y);
    effErr = mix(effErr, bone, body * 0.90);
    effErr = mix(effErr, vec3(0.05, 0.010, 0.015), clamp(cuts, 0.0, 1.0) * body);
    effErr = mix(effErr, vec3(0.08, 0.020, 0.030), stripes * 0.85);
    vec2 pp = vec2(abs(sp.x), sp.y) - vec2(0.30, 0.06);           // 红瞳 (脉动)
    float pupil = smoothstep(0.11, 0.0, length(pp * vec2(1.0, 1.3)));
    effErr += vec3(0.95, 0.10, 0.08) * pupil * (0.55 + 0.45 * sin(t * 3.2)) * body;
    float glowSk = exp(-max(head, 0.0) * 3.5) * (1.0 - body);     // 轮廓外发光
    effErr += vec3(0.50, 0.08, 0.10) * glowSk * (0.6 + 0.4 * sin(t * 2.1));
    float vig = smoothstep(1.15, 0.35, length((uv - 0.5) * vec2(aspect, 1.0)));
    effErr *= 0.55 + 0.45 * vig;                                  // 暗角

    // ════ 粒子 (共用一趟, 参数按 one-hot 权重混合) ════
    // run=星尘 done=萤火虫 attn=琥珀粒子 err=余烬
    float pSpeed = 0.25 * wBlue + 0.35 * wGreen + 1.00 * wAmber + 0.80 * wRed;
    float pSize  = 0.05 * wBlue + 0.09 * wGreen + 0.10 * wAmber + 0.07 * wRed;
    float pThr   = 0.90 * wBlue + 0.80 * wGreen + 0.75 * wAmber + 0.82 * wRed;
    float pSeed  = 7.0  * wBlue + 3.0  * wGreen + 0.00 * wAmber + 11.0 * wRed;
    vec3  pCol   = vec3(0.90, 0.95, 1.00) * 0.25 * wBlue
                 + vec3(0.45, 0.95, 0.55) * 0.45 * wGreen
                 + vec3(1.00, 0.60, 0.16) * 0.50 * wAmber
                 + vec3(1.00, 0.35, 0.10) * 0.40 * wRed;
    float parts = 0.0;
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float scale = 12.0 + fi * 9.0;
        vec2 p = uv * scale * vec2(aspect, 1.0);
        p.y -= t * pSpeed * (0.6 + 0.35 * fi);
        p.x += sin(t * 0.6 + fi * 2.0 + uv.y * 4.0) * 0.3;
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
    vec3 eff = effRun * wBlue + effDone * wGreen + effAttn * wAmber + effErr * wRed;
    eff += pCol * parts;
    float isBg = 1.0 - smoothstep(0.06, 0.18, distance(tex.rgb, bg));
    fragColor = vec4(mix(tex.rgb, eff, isBg * gate), tex.a);
}
