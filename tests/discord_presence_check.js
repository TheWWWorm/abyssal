'use strict';
// Synthetic local IPC peers; never connects to an installed Discord client.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const net = require('node:net');
const os = require('node:os');
const path = require('node:path');
const {spawn} = require('node:child_process');
const {once} = require('node:events');
const {DiscordPresence, frame, ipcPaths} = require('../desktop/discord_presence.js');

const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
async function until(condition) {
  const end = Date.now() + 4000;
  while (!condition()) { assert.ok(Date.now() < end, 'IPC condition timed out'); await wait(5); }
}

async function peer(t, customPath) {
  const folder = fs.mkdtempSync(path.join(os.tmpdir(), 'abyssal-discord-'));
  const socketPath = customPath || (process.platform === 'win32' ? `\\\\?\\pipe\\abyssal-test-${process.pid}-${path.basename(folder)}` : path.join(folder, 'discord-ipc-7'));
  const messages = [], connections = [];
  const server = net.createServer(socket => {
    connections.push(socket);
    let input = Buffer.alloc(0);
    socket.on('error', () => {});
    socket.on('data', chunk => {
      input = Buffer.concat([input, chunk]);
      while (input.length >= 8 && input.length >= input.readUInt32LE(4) + 8) {
        const length = input.readUInt32LE(4), opcode = input.readUInt32LE(0);
        const raw = input.subarray(8, 8 + length); input = input.subarray(8 + length);
        messages.push({opcode, data: JSON.parse(raw.toString()), raw, socket});
      }
    });
  });
  server.listen(socketPath); await once(server, 'listening');
  t.after(async () => {
    for (const connection of connections) connection.destroy();
    await new Promise(resolve => server.close(resolve));
    fs.rmSync(folder, {recursive: true, force: true});
  });
  return {socketPath, messages, connections, server};
}

async function ready(p) {
  await until(() => p.messages.some(item => item.opcode === 0));
  const hello = p.messages.find(item => item.opcode === 0);
  assert.deepEqual(hello.data, {v: 1, client_id: '1561821965210222642'});
  // Deliver a split header/body followed by another frame in the same chunk.
  const packet = frame(1, {cmd: 'DISPATCH', evt: 'READY'});
  hello.socket.write(packet.subarray(0, 3));
  hello.socket.write(Buffer.concat([packet.subarray(3), frame(3, {ping: 'alive'})]));
  await until(() => p.messages.some(item => item.data.cmd === 'SET_ACTIVITY'));
  return hello.socket;
}

test('Discovers every IPC slot and sandboxed desktop locations', () => {
  const windows = ipcPaths('win32', {});
  assert.equal(windows.length, 10); assert.equal(windows[9], '\\\\?\\pipe\\discord-ipc-9');
  const unix = ipcPaths('linux', {XDG_RUNTIME_DIR: '/run/example', TMPDIR: '/private/tmp'});
  assert.equal(unix[0], '/run/example/discord-ipc-0');
  assert.ok(unix.includes('/run/example/app/com.discordapp.Discord/discord-ipc-9'));
  assert.ok(unix.includes('/private/tmp/discord-ipc-7'));
  assert.ok(unix.includes('/tmp/discord-ipc-0'));
});

test('Frames activity for the game PID, handles fragmented input and ping, clears on stop', async t => {
  const p = await peer(t);
  const presence = new DiscordPresence('1561821965210222642', 1234, {paths: [p.socketPath], interval: 30});
  t.after(() => presence.stop());
  presence.update({details: 'Exploring the ocean', state: 'Piloting Ino'});
  await ready(p);
  const sent = p.messages.find(item => item.data.cmd === 'SET_ACTIVITY');
  assert.equal(sent.data.args.pid, 1234);
  assert.deepEqual(sent.data.args.activity, {details: 'Exploring the ocean', state: 'Piloting Ino'});
  await until(() => p.messages.some(item => item.opcode === 4));
  assert.deepEqual(p.messages.find(item => item.opcode === 4).data, {ping: 'alive'});
  presence.stop();
  await until(() => p.messages.some(item => item.data.args?.activity === null));
});

test('Coalesces fast changes, waits for acknowledgement and avoids duplicate updates', async t => {
  const p = await peer(t);
  const presence = new DiscordPresence('1561821965210222642', 1234, {paths: [p.socketPath], interval: 80});
  t.after(() => presence.stop());
  presence.update({details: 'At a station'}); const socket = await ready(p);
  const first = p.messages.find(item => item.data.cmd === 'SET_ACTIVITY');
  presence.update({details: 'At the hangar'}); presence.update({details: 'Piloting a new ship'});
  await wait(100);
  assert.equal(p.messages.filter(item => item.data.cmd === 'SET_ACTIVITY').length, 1);
  socket.write(frame(1, {cmd: 'SET_ACTIVITY', nonce: first.data.nonce}));
  await until(() => p.messages.filter(item => item.data.cmd === 'SET_ACTIVITY').length === 2);
  const latest = p.messages.filter(item => item.data.cmd === 'SET_ACTIVITY')[1];
  assert.equal(latest.data.args.activity.details, 'Piloting a new ship');
  socket.write(frame(1, {cmd: 'SET_ACTIVITY', nonce: latest.data.nonce}));
  presence.update({details: 'Piloting a new ship'}); await wait(100);
  assert.equal(p.messages.filter(item => item.data.cmd === 'SET_ACTIVITY').length, 2);
});

test('Retries absent sockets and restores the newest activity after Discord restarts', async t => {
  const p = await peer(t);
  const missing = process.platform === 'win32' ? p.socketPath + '-missing' : p.socketPath + '-missing';
  const presence = new DiscordPresence('1561821965210222642', 1234, {paths: [missing, p.socketPath], retry: 20, timeout: 50, interval: 20});
  t.after(() => presence.stop());
  presence.update({details: 'Exploring'}); const socket = await ready(p);
  socket.destroy(); presence.update({details: 'In combat'});
  await until(() => p.messages.filter(item => item.opcode === 0).length >= 2);
  const hello = p.messages.filter(item => item.opcode === 0).at(-1);
  hello.socket.write(frame(1, {evt: 'READY'}));
  await until(() => p.messages.some(item => item.data.args?.activity?.details === 'In combat'));
});

test('Rejects oversized and malformed inbound frames and retries', async t => {
  const p = await peer(t);
  const presence = new DiscordPresence('1561821965210222642', 1234, {paths: [p.socketPath], retry: 20, timeout: 50});
  t.after(() => presence.stop());
  presence.update({details: 'Exploring'}); const socket = await ready(p);
  const header = Buffer.alloc(8); header.writeUInt32LE(1, 0); header.writeUInt32LE(0xffffffff, 4);
  socket.write(header);
  await until(() => p.messages.filter(item => item.opcode === 0).length >= 2);
  p.messages.filter(item => item.opcode === 0).at(-1).socket.write(frame(1, null));
  await until(() => p.messages.filter(item => item.opcode === 0).length >= 3);
});

test('Helper exits and clears activity when the game closes its pipe', async t => {
  const folder = fs.mkdtempSync(path.join(os.tmpdir(), 'abyssal-helper-'));
  t.after(() => fs.rmSync(folder, {recursive: true, force: true}));
  if (process.platform === 'win32') return; // Fixed Discord pipe names would collide with a running client.
  const p = await peer(t, path.join(folder, 'discord-ipc-0'));
  const child = spawn(process.execPath, [path.join(__dirname, '../desktop/discord_presence.js'), '1561821965210222642', String(process.pid)], {
    env: {...process.env, XDG_RUNTIME_DIR: folder}, stdio: ['pipe', 'pipe', 'pipe']
  });
  t.after(() => { if (child.exitCode === null) child.kill(); });
  const exited = once(child, 'exit');
  child.stdin.write(JSON.stringify({details: 'Exploring', state: 'Piloting Ino'}) + '\n');
  await ready(p);
  child.stdin.end();
  await until(() => p.messages.some(item => item.data.args?.activity === null));
  const [code] = await exited; assert.equal(code, 0);
});

test('Godot delivers an activity through the real nonblocking helper pipe', {skip: !process.env.ABYSSAL_TEST_GODOT}, async t => {
  if (process.platform === 'win32') return;
  const folder = fs.mkdtempSync(path.join(os.tmpdir(), 'abyssal-godot-'));
  t.after(() => fs.rmSync(folder, {recursive: true, force: true}));
  const p = await peer(t, path.join(folder, 'discord-ipc-0'));
  const root = path.resolve(__dirname, '..');
  const child = spawn(process.env.ABYSSAL_TEST_GODOT, ['--headless', '--path', path.join(root, 'game'), '--script', path.join(root, 'tests/discord_presence_check.gd'), '--', '--pipe-probe'], {
    env: {...process.env, XDG_RUNTIME_DIR: folder, ABYSSAL_NODE_PATH: process.execPath}, stdio: ['ignore', 'pipe', 'pipe']
  });
  t.after(() => { if (child.exitCode === null) child.kill(); });
  let output = ''; child.stdout.on('data', data => { output += data; }); child.stderr.on('data', data => { output += data; });
  const exited = once(child, 'exit');
  await ready(p);
  await until(() => p.messages.some(item => item.data.args?.activity === null));
  const [code] = await exited; assert.equal(code, 0, output);
  const activity = p.messages.find(item => item.data.args?.activity?.state === 'Piloting Pipe test ship');
  assert.ok(activity); assert.equal(activity.data.args.pid, child.pid);
  assert.ok(!output.includes('SCRIPT ERROR'), output);
});
