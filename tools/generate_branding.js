#!/usr/bin/env node
'use strict';
// Deterministic layout, resizing and icon containers from the approved master.
// Development only: npm install sharp outside the source tree, then set
// ABYSSAL_SHARP_PATH to that installation's sharp package if needed.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const sharp = require(process.env.ABYSSAL_SHARP_PATH || 'sharp');
const root = path.resolve(__dirname, '..');
const source = path.join(root, 'game/ui/abyssal-icon.png');
const hash = data => crypto.createHash('sha256').update(data).digest('hex');
const written = [];

function save(name, data) {
  fs.writeFileSync(path.join(root, name), data); written.push(name);
}
async function png(size) {
  return sharp(source).resize(size, size, {kernel: 'lanczos3'}).png().toBuffer();
}
async function main() {
  const before = hash(fs.readFileSync(source));
  const master = await sharp(source).metadata();
  if (master.width !== 1024 || master.height !== 1024) throw Error('The approved master must remain 1024 × 1024.');
  const sizes = [16, 24, 32, 48, 64, 128, 256];
  const frames = await Promise.all(sizes.map(png));
  const directory = Buffer.alloc(6 + 16 * sizes.length);
  directory.writeUInt16LE(1, 2); directory.writeUInt16LE(sizes.length, 4);
  let offset = directory.length;
  for (let i = 0; i < sizes.length; i++) {
    const at = 6 + i * 16;
    directory[at] = directory[at + 1] = sizes[i] === 256 ? 0 : sizes[i];
    directory.writeUInt16LE(1, at + 4); directory.writeUInt16LE(32, at + 6);
    directory.writeUInt32LE(frames[i].length, at + 8); directory.writeUInt32LE(offset, at + 12);
    offset += frames[i].length;
  }
  save('game/ui/abyssal-icon.ico', Buffer.concat([directory, ...frames]));
  const chunks = [];
  for (const [type, size] of [['icp4', 16], ['icp5', 32], ['icp6', 64], ['ic07', 128], ['ic08', 256], ['ic09', 512], ['ic10', 1024]]) {
    const data = await png(size), header = Buffer.alloc(8);
    header.write(type, 0); header.writeUInt32BE(data.length + 8, 4);
    chunks.push(header, data);
  }
  const header = Buffer.alloc(8); header.write('icns', 0);
  header.writeUInt32BE(8 + chunks.reduce((total, part) => total + part.length, 0), 4);
  save('game/ui/abyssal-icon.icns', Buffer.concat([header, ...chunks]));
  // One compact mark and its proper name. Transparent padding lets Godot and
  // the browser fit the same group to the shorter window dimension.
  const title = await sharp({text: {
    text: '<span foreground="#d6e8ee" weight="bold" letter_spacing="10240">ABYSSAL</span>',
    font: 'DejaVu Sans 64', rgba: true,
  }}).png().toBuffer({resolveWithObject: true});
  const iconSize = 512, gap = 42;
  // Builds with a vendor's graphics SDK credit it under the name: AMD's
  // white FSR lockups, as AMD's FSR guidelines provide them, in a row of
  // equal cells, and a text line for NVIDIA DLSS, whose licence asks for a
  // splash attribution. Each cell may carry a caption below its logo.
  const amd = ['amd-fsr-upscaling-white.png', 'amd-fsr-frame-generation-white.png']
    .map(name => ({file: path.join(root, 'game/ui/vendors', name)}));
  const text = async (markup, size) => sharp({text: {text: markup, font: 'DejaVu Sans ' + size, rgba: true}})
    .png().toBuffer({resolveWithObject: true}).then(r => ({input: r.data, width: r.info.width, height: r.info.height}));
  async function row(cells) {
    const cell = 256, logo = 144, between = 40;
    const captions = await Promise.all(cells.map(c => c.caption ? text('<span foreground="white">' + c.caption + '</span>', 24) : null));
    const height = logo + Math.max(0, ...captions.map(c => c ? 10 + c.height : 0));
    const width = cells.length * cell + (cells.length - 1) * between;
    const layers = [];
    for (let i = 0; i < cells.length; i++) {
      let picture = sharp(cells[i].file);
      if (cells[i].region) picture = picture.extract(cells[i].region);
      const fitted = await picture.resize(cell, logo, {fit: 'inside', kernel: 'lanczos3'}).png().toBuffer({resolveWithObject: true});
      const x = i * (cell + between);
      layers.push({input: fitted.data, left: x + Math.floor((cell - fitted.info.width) / 2), top: Math.floor((logo - fitted.info.height) / 2)});
      if (captions[i]) layers.push({input: captions[i].input, left: x + Math.floor((cell - captions[i].width) / 2), top: logo + 10});
    }
    const data = await sharp({create: {width, height, channels: 4, background: {r: 0, g: 0, b: 0, alpha: 0}}}).composite(layers).png().toBuffer();
    return {input: data, width, height, gap: 56};
  }
  async function splash(line, cells) {
    const parts = [{input: title.data, width: title.info.width, height: title.info.height}];
    if (line) parts.push({gap: 30, ...await text(line, 28)});
    if (cells) parts.push(await row(cells));
    const height = iconSize + parts.reduce((total, part) => total + (part.gap || gap) + part.height, 0);
    let y = Math.floor((1024 - height) / 2);
    const layers = [{input: await png(iconSize), left: 256, top: y}];
    y += iconSize;
    for (const part of parts) {
      y += part.gap || gap;
      layers.push({input: part.input, left: Math.floor((1024 - part.width) / 2), top: y});
      y += part.height;
    }
    return sharp({create: {width: 1024, height: 1024, channels: 4, background: {r: 0, g: 0, b: 0, alpha: 0}}})
      .composite(layers).png().toBuffer();
  }
  const dlss = '<span foreground="#8fb3bd" letter_spacing="2048">Powered by NVIDIA DLSS</span>';
  save('game/ui/abyssal-splash.png', await splash(null));
  save('game/ui/abyssal-splash-fsr.png', await splash(null, amd));
  save('game/ui/abyssal-splash-dlss.png', await splash(dlss, amd));
  // NVIDIA's own GeForce RTX artwork needs NVIDIA's written approval, so it
  // is not part of the source: --nvidia-badge <png> <directory> writes the
  // proposed splash with it outside the tree, for review.
  const badge = process.argv.indexOf('--nvidia-badge');
  if (badge > 0) {
    const [file, directory] = process.argv.slice(badge + 1, badge + 3);
    const cells = [{file, region: {left: 290, top: 278, width: 2420, height: 730}, caption: 'NVIDIA DLSS'}, ...amd];
    fs.mkdirSync(directory, {recursive: true});
    fs.writeFileSync(path.join(directory, 'abyssal-splash-nvidia.png'), await splash(null, cells));
  }
  for (const [name, size] of [['favicon', 64], ['apple-touch-icon', 180], ['icon-192', 192], ['icon-512', 512]]) {
    save('browser/' + name + '.png', await png(size));
  }
  if (before !== hash(fs.readFileSync(source))) throw Error('The approved master was changed.');
  console.log('Generated ' + written.length + ' branding assets; approved master unchanged: ' + before);
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
