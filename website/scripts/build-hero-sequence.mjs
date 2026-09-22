// Optional asset-build tool: run from website with Node, sharp and ffmpeg available.
// Source PNGs are generated keyframes, never a procedural approximation of the art.
import sharp from 'sharp';
import { execFileSync } from 'node:child_process';
import { mkdtemp, mkdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
const site = fileURLToPath(new URL('../', import.meta.url));
const input = resolve(site, '../docs/assets/hero-motion-v2/keyframes/frame-%02d.png');
const output = resolve(site, 'public/brand/motion-v2');
const temp = await mkdtemp(join(tmpdir(), 'tokenmini-frames-'));
try {
  // Alpha gets converted to limited-range luma for interpolation. Restore 0–255
  // explicitly before alphamerge, otherwise the whole canvas becomes translucent.
  const filter = '[0:v]scale=1152:648:flags=lanczos,format=rgba,tpad=stop_mode=clone:stop_duration=1,format=rgba,split[c][a];[c]format=yuv444p,minterpolate=fps=18:mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1[rgb];[a]alphaextract,format=yuv444p,minterpolate=fps=18:mi_mode=blend,extractplanes=y,lut=y=(val-16)*255/219[alpha];[rgb][alpha]alphamerge,format=rgba[out]';
  execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-framerate', '2', '-i', input, '-filter_complex', filter, '-map', '[out]', '-frames:v', '32', '-start_number', '0', join(temp, 'frame-%03d.png')], { stdio: 'inherit' });
  for (const [size, width, height] of [['desktop', 1152, 648], ['mobile', 640, 360]]) {
    await mkdir(join(output, size), { recursive: true });
    for (let index = 0; index < 32; index++) {
      const name = `frame-${String(index).padStart(3, '0')}`;
      await sharp(join(temp, `${name}.png`)).resize(width, height).webp({ quality: 82, alphaQuality: 95, effort: 5 }).toFile(join(output, size, `${name}.webp`));
    }
  }
  await sharp(input.replace('%02d', '00')).webp({ quality: 87, alphaQuality: 100, effort: 6 }).toFile(join(output, 'poster.webp'));
} finally { await rm(temp, { recursive: true, force: true }); }
console.log('Encoded 32 transparent frames per viewport size.');
