#version 460 core
#include <flutter/runtime_effect.glsl>

// ─────────────────────────────────────────────────────────────
// 液态玻璃「透镜色散」自定义 shader v2（floatica / iOS 26 配方融合）
//
// 输入：导航栏背后内容的截取条带（1.5x 逻辑分辨率纹理）
// 效果：
//   1. 3×3 加权模糊（玻璃磨砂）
//   2. 圆角矩形 SDF 边界掩码（内部玻璃 / 边缘色散带 / 外部彩色光晕）
//   3. 径向 RGB 色散：边缘处 R/B 通道按圆心方向分离采样 —— 真实透镜色散，
//      色散条纹颜色来自背景内容本身（亮边缘 → 青/品红镶边）
//   4. 饱和度提升（floatica saturationBoost 1.2，玻璃透出的背景更鲜艳）
//   5. 内阴影（边缘内侧暗化，出玻璃厚度，iOS 26 innerShadow）
//   6. 多层高光（顶部边缘高光带 + 左上→右下柔和 sheen，iOS 26 specular）
//   7. 噪点双倍率纹理（细噪 + 大颗粒，材质感，消除 banding）
//   8. 玻璃底色叠加
// ─────────────────────────────────────────────────────────────

uniform vec2 u_texSize;        // 条带尺寸（逻辑像素）
uniform vec2 u_size;           // 玻璃面板尺寸（逻辑像素）
uniform vec2 u_origin;         // 面板左上角在条带纹理内的偏移（逻辑像素）
uniform float u_radius;        // 面板圆角半径
uniform float u_blur;          // 模糊强度（逻辑像素）
uniform float u_dispersion;    // 色散偏移（逻辑像素）
uniform float u_edgeGlow;      // 边缘光晕强度
uniform float u_time;          // 时间（噪点抖动）
uniform vec4 u_tint;           // 玻璃底色（rgb + alpha）
uniform float u_saturation;    // 饱和度提升（1.0 = 不变）
uniform sampler2D u_texture;   // 截取条带纹理（声明在最后，对齐 Flutter uniform 索引约定）

out vec4 fragColor;

// 圆角矩形 SDF（p 相对矩形中心，b 半尺寸，r 圆角）
float roundedRectSDF(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + vec2(r);
  return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// 3×3 加权模糊（中心权重高）
vec3 sampleBlur(vec2 uv, float spread) {
  vec2 texel = vec2(1.0) / u_texSize;
  vec3 sum = vec3(0.0);
  float wSum = 0.0;
  for (int y = -1; y <= 1; y++) {
    for (int x = -1; x <= 1; x++) {
      vec2 off = vec2(float(x), float(y)) * texel * spread;
      float w = 1.0 / (1.0 + abs(float(x)) + abs(float(y)));
      sum += texture(u_texture, uv + off).rgb * w;
      wSum += w;
    }
  }
  return sum / wSum;
}

// 饱和度提升（保持亮度，只拉高色度）
vec3 boostSaturation(vec3 c, float s) {
  float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
  return mix(vec3(luma), c, s);
}

void main() {
  vec2 p = gl_FragCoord.xy;              // 当前像素在条带坐标系中的位置
  vec2 uv = p / u_texSize;               // 采样坐标
  vec2 center = u_origin + u_size * 0.5; // 面板中心
  vec2 halfSize = u_size * 0.5;

  // 到面板圆角矩形的距离（负值 = 面板内部）
  float d = roundedRectSDF(p - center, halfSize - u_radius, u_radius);

  // 掩码
  float inside    = 1.0 - smoothstep(-2.0, 0.0, d);                            // 面板内部
  float edgeBand  = 1.0 - smoothstep(-4.5, 0.0, d);                            // 边界内侧 4.5px 色散带
  float halo      = (1.0 - smoothstep(0.0, 16.0, d)) * (1.0 - smoothstep(-1.2, 0.0, d)); // 边界外侧 16px 光晕

  float alpha = inside + halo * 0.9;

  // 玻璃底（模糊背景）
  vec3 blurred = sampleBlur(uv, u_blur);

  // 径向色散：R 外偏、B 内偏（G 不动），偏移随边缘带增强
  vec2 dir = p - center;
  float len = length(dir);
  if (len < 0.001) {
    dir = vec2(1.0, 0.0);
  } else {
    dir /= len;
  }
  float dispPx = u_dispersion * edgeBand;
  vec3 chromatic;
  chromatic.r = sampleBlur(uv + dir * dispPx / u_texSize, u_blur).r;
  chromatic.g = blurred.g;
  chromatic.b = sampleBlur(uv - dir * dispPx / u_texSize, u_blur).b;

  // 内部：边缘处色散最强，向中心平滑过渡回玻璃底
  vec3 col = mix(blurred, chromatic, edgeBand * 0.85);

  // 真实透镜色散光晕（增强 2.4x）：色散差异放大彩色镶边 + 外圈彩虹晕
  vec3 fringe = (chromatic - blurred) * 2.4;
  col += fringe * edgeBand * u_edgeGlow;
  col += fringe * halo * u_edgeGlow * 0.9;

  // 饱和度提升（floatica saturationBoost）
  col = boostSaturation(col, u_saturation);

  // 内阴影：边界内侧 0~14px 渐暗，出玻璃厚度（iOS 26 innerShadow）
  float innerShadow = smoothstep(-14.0, 0.0, d) * inside;
  col *= 1.0 - innerShadow * 0.20;

  // 多层高光：
  // 1) 顶部边缘高光带（specular highlight，顶部 14px 渐淡）
  float topDist = p.y - (center.y - halfSize.y);
  float topBand = (1.0 - smoothstep(0.0, 14.0, topDist)) * inside;
  col += vec3(0.55, 0.60, 0.72) * topBand * 0.12;
  // 2) 左上→右下柔和 sheen（左上角更亮，模拟环境光）
  vec2 norm = (p - (center - halfSize)) / u_size; // 0~1 归一化位置
  float sheen = smoothstep(0.0, 0.6, 1.0 - norm.x - norm.y) * inside;
  col += vec3(1.0) * sheen * 0.05;

  // 玻璃底色叠加
  col = mix(col, u_tint.rgb, u_tint.a * inside);

  // 噪点双倍率：细噪 + 大颗粒（floatica noiseOpacity 0.05 同级，材质感 + 防 banding）
  float fineNoise = hash(p + vec2(u_time * 1.7, 0.0));
  float coarseNoise = hash(floor(p / 2.0) + vec2(u_time * 0.7, 1.0));
  col += (fineNoise + coarseNoise * 0.6 - 0.8) * 0.05 * inside;

  fragColor = vec4(col, alpha);
}
