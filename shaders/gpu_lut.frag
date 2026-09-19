// Flutter fragment shader (GLSL ES)
// Applies a 3D LUT packed into a 2D texture to the source image.
precision highp float;

// Source camera planes as textures
// uY: full-res luminance plane, stored in the R channel
// uUV: half-res chroma plane, U in R channel, V in G channel
uniform sampler2D uY;
uniform sampler2D uUV;
// Packed 2D LUT texture
uniform sampler2D uLut2D;

uniform float uSize;   // LUT cube size (e.g., 33)
uniform float uMix;    // mix strength [0..1]
// Color conversion options
// uMode: 0.0 = BT.709 full-range, 1.0 = BT.601 limited-range
uniform float uMode;
// uSwapUV: 0.0 = normal, 1.0 = swap U and V channels
uniform float uSwapUV;
// LUT atlas/texture layout (generic, compatible with glsl-lut tiling)
uniform float uLutW;     // LUT texture width (pixels)
uniform float uLutH;     // LUT texture height (pixels)
uniform float uTilesX;   // number of tiles along X
uniform float uTilesY;   // number of tiles along Y
// Flip LUT texture Y coordinate (for compatibility with some pipelines)
uniform float uFlipY;    // 0.0 = normal, 1.0 = flip Y

// Destination size in pixels
uniform float uDstW;
uniform float uDstH;

// Source image size in pixels
uniform float uSrcW;
uniform float uSrcH;
// UV plane size in pixels (typically src/2)
uniform float uUvW;
uniform float uUvH;

out vec4 fragColor;

// Maps destination fragCoord to source pixel coords for contain-fit (no crop).
// Returns coordinates in source pixel space.
vec2 mapContain(vec2 fragCoord) {
  float dstAspect = uDstW / uDstH;
  float srcAspect = uSrcW / uSrcH;
  float drawW;
  float drawH;
  // contain: fit inside destination; may letterbox
  if (dstAspect > srcAspect) {
    // destination is wider -> match height
    drawH = uDstH;
    drawW = drawH * srcAspect;
  } else {
    // destination is taller -> match width
    drawW = uDstW;
    drawH = drawW / srcAspect;
  }
  // Map fragCoord relative to centered draw rect to source pixels
  vec2 center = vec2(uDstW * 0.5, uDstH * 0.5);
  vec2 local = fragCoord - center;
  // Scale to src pixel space
  vec2 scaled = vec2(local.x * (uSrcW / drawW), local.y * (uSrcH / drawH));
  vec2 srcCoord = vec2(uSrcW * 0.5, uSrcH * 0.5) + scaled;
  return srcCoord;
}

// Maps destination fragCoord to source pixel coords for cover-fit (crop to fill).
// Returns coordinates in source pixel space.
vec2 mapCover(vec2 fragCoord) {
  float dstAspect = uDstW / uDstH;
  float srcAspect = uSrcW / uSrcH;
  float drawW;
  float drawH;
  // cover: fill destination; may crop
  if (dstAspect > srcAspect) {
    // destination is wider -> match width
    drawW = uDstW;
    drawH = drawW / srcAspect;
  } else {
    // destination is taller -> match height
    drawH = uDstH;
    drawW = drawH * srcAspect;
  }
  vec2 center = vec2(uDstW * 0.5, uDstH * 0.5);
  vec2 local = fragCoord - center;
  vec2 scaled = vec2(local.x * (uSrcW / drawW), local.y * (uSrcH / drawH));
  vec2 srcCoord = vec2(uSrcW * 0.5, uSrcH * 0.5) + scaled;
  return srcCoord;
}

// Sample the packed 2D LUT image at integer coordinates (r,g,b in [0..N-1]).
// Packing: width = N*N, height = N; tiles of width N laid horizontally for each B slice.
// Compute UV into a generic tiled atlas of slices.
// tilesX * tilesY >= uSize slices; each tile is N x N pixels.
// texSize is the total LUT texture size in pixels.
vec2 sampleLutUV(float rr, float gg, float bb, float tilesX, float tilesY, vec2 texSize) {
  float tileIndex = bb;
  float tx = mod(tileIndex, tilesX);
  float ty = floor(tileIndex / tilesX);
  float tileW = texSize.x / tilesX;
  float tileH = texSize.y / tilesY;
  float x = rr + tx * tileW + 0.5;
  float y = gg + ty * tileH + 0.5;
  vec2 uv = vec2(x / texSize.x, y / texSize.y);
  if (uFlipY >= 0.5) {
    uv.y = 1.0 - uv.y;
  }
  return uv;
}

vec3 sampleLut(float rr, float gg, float bb) {
  // Generic atlas sampler using provided uniforms; works for our pack when
  // tilesX = uSize, tilesY = 1, tex = (uSize*uSize, uSize)
  vec2 texSize = vec2(uLutW, uLutH);
  vec2 uv = sampleLutUV(rr, gg, bb, uTilesX, uTilesY, texSize);
  return texture(uLut2D, uv).rgb;
}

void main() {
  vec2 fragCoord = gl_FragCoord.xy;
  // Map to source image pixel coords using cover-fit to match CameraPreview
  vec2 srcCoord = mapCover(fragCoord);
  // Sample source; if outside, make transparent
  if (srcCoord.x < 0.0 || srcCoord.y < 0.0 || srcCoord.x >= uSrcW || srcCoord.y >= uSrcH) {
    fragColor = vec4(0.0);
    return;
  }
  // Convert pixel coordinates to normalized texture coordinates.
  // For normalized sampling, both Y and UV planes use [0..1] UVs.
  // Since the UV plane is half resolution, the correct normalized
  // coordinates are still just srcCoord normalized by the source size.
  // Using srcCoord/uUv dims would exceed 1.0; use the same normalized srcUV.
  vec2 srcUV = srcCoord / vec2(uSrcW, uSrcH);
  // 确保坐标系以左下角为(0,0)：不翻转Y坐标，保持OpenGL标准坐标系
  // srcUV.y = 1.0 - srcUV.y; // 注释掉Y坐标翻转
  vec2 uvUV = srcUV;

  // Sample Y (full res) and UV (half res). Values in [0..1]
  float yN = texture(uY, srcUV).r;
  vec2 uvN = texture(uUV, uvUV).rg;
  // Optional swap of U/V depending on device format
  float uN = mix(uvN.x, uvN.y, step(0.5, uSwapUV));
  float vN = mix(uvN.y, uvN.x, step(0.5, uSwapUV));

  // Center chroma around 0
  float U = uN - 0.5;
  float V = vN - 0.5;

  // Two modes:
  //  - BT.709 full-range: R= y + 1.280*V; G= y - 0.215*U - 0.381*V; B= y + 2.128*U
  //  - BT.601 limited-range: y' = 1.164*(yN - 16/255); then
  //      R= y' + 1.596*V; G= y' - 0.391*U - 0.813*V; B= y' + 2.018*U
  // Compute both and select by uMode to avoid dynamic branches on some GPUs
  float y601 = 1.164 * max(yN - (16.0/255.0), 0.0);
  vec3 rgb709 = vec3(
      clamp(yN + 1.280 * V, 0.0, 1.0),
      clamp(yN - 0.215 * U - 0.381 * V, 0.0, 1.0),
      clamp(yN + 2.128 * U, 0.0, 1.0)
  );
  vec3 rgb601 = vec3(
      clamp(y601 + 1.596 * V, 0.0, 1.0),
      clamp(y601 - 0.391 * U - 0.813 * V, 0.0, 1.0),
      clamp(y601 + 2.018 * U, 0.0, 1.0)
  );
  vec3 rgb = mix(rgb709, rgb601, step(0.5, uMode));

  float N = uSize - 1.0;
  float rf = rgb.r * N;
  float gf = rgb.g * N;
  float bf = rgb.b * N;
  float r0 = floor(rf);
  float g0 = floor(gf);
  float b0 = floor(bf);
  float r1 = min(r0 + 1.0, N);
  float g1 = min(g0 + 1.0, N);
  float b1 = min(b0 + 1.0, N);
  float rFrac = rf - r0;
  float gFrac = gf - g0;
  float bFrac = bf - b0;

  vec3 c000 = sampleLut(r0, g0, b0);
  vec3 c100 = sampleLut(r1, g0, b0);
  vec3 c010 = sampleLut(r0, g1, b0);
  vec3 c110 = sampleLut(r1, g1, b0);
  vec3 c001 = sampleLut(r0, g0, b1);
  vec3 c101 = sampleLut(r1, g0, b1);
  vec3 c011 = sampleLut(r0, g1, b1);
  vec3 c111 = sampleLut(r1, g1, b1);

  vec3 c00 = mix(c000, c100, rFrac);
  vec3 c10 = mix(c010, c110, rFrac);
  vec3 c01 = mix(c001, c101, rFrac);
  vec3 c11 = mix(c011, c111, rFrac);
  vec3 c0 = mix(c00, c10, gFrac);
  vec3 c1 = mix(c01, c11, gFrac);
  vec3 lutRgb = mix(c0, c1, bFrac);

  vec3 outRgb = mix(rgb, lutRgb, clamp(uMix, 0.0, 1.0));
  fragColor = vec4(outRgb, 1.0);
}
