'use strict';
// Local Discord IPC only. No account credentials, HTTP requests or dependencies.
const net = require('node:net');
const os = require('node:os');
const path = require('node:path');
const readline = require('node:readline');

const MAX_FRAME = 64 * 1024;

function ipcPaths(platform = process.platform, env = process.env) {
  if (platform === 'win32') return Array.from({length: 10}, (_, n) => `\\\\?\\pipe\\discord-ipc-${n}`);
  const roots = [...new Set([env.XDG_RUNTIME_DIR, env.TMPDIR, env.TMP, env.TEMP, os.tmpdir(), '/tmp'].filter(Boolean))];
  // Flatpak Discord exposes its socket in app/com.discordapp.Discord.
  const folders = [...new Set(roots.flatMap(root => [root, path.join(root, 'app/com.discordapp.Discord')]))];
  return folders.flatMap(root => Array.from({length: 10}, (_, n) => path.join(root, `discord-ipc-${n}`)));
}

function frame(opcode, data) {
  const body = Buffer.isBuffer(data) ? data : Buffer.from(JSON.stringify(data));
  const header = Buffer.alloc(8);
  header.writeUInt32LE(opcode, 0); header.writeUInt32LE(body.length, 4);
  return Buffer.concat([header, body]);
}

class DiscordPresence {
  constructor(clientId, pid, options = {}) {
    this.clientId = clientId; this.pid = pid;
    this.paths = options.paths || ipcPaths();
    this.interval = options.interval ?? 15000;
    this.retry = options.retry ?? 15000;
    this.timeout = options.timeout ?? 1500;
    this.socket = null; this.ready = false; this.stopped = false;
    this.activity = null; this.last = undefined; this.sentAt = 0; this.nonce = 0;
    this.pending = null; this.timer = null; this.attempt = null;
  }

  update(activity) {
    this.activity = activity;
    if (!this.socket && !this.timer && !this.stopped) this.connect(0);
    this.flush();
  }

  connect(index) {
    if (this.stopped) return;
    if (index >= this.paths.length) {
      this.timer = setTimeout(() => { this.timer = null; this.connect(0); }, this.retry);
      return;
    }
    const socket = net.createConnection(this.paths[index]);
    this.socket = socket; this.ready = false; this.last = undefined; this.pending = null;
    let input = Buffer.alloc(0);
    let connected = false;
    this.attempt = setTimeout(() => socket.destroy(), this.timeout);
    socket.on('connect', () => { connected = true; socket.write(frame(0, {v: 1, client_id: this.clientId})); });
    socket.on('error', () => {}); // Discord is optional and may not be running.
    socket.on('close', () => {
      clearTimeout(this.attempt); this.attempt = null;
      this.socket = null; this.ready = false; this.pending = null;
      clearTimeout(this.timer); this.timer = null;
      if (this.stopped) return;
      if (!connected) this.connect(index + 1);
      else this.timer = setTimeout(() => { this.timer = null; this.connect(0); }, this.retry);
    });
    socket.on('data', chunk => {
      input = Buffer.concat([input, chunk]);
      while (input.length >= 8) {
        const opcode = input.readUInt32LE(0), length = input.readUInt32LE(4);
        if (length > MAX_FRAME) { socket.destroy(); return; }
        if (input.length < length + 8) break;
        const body = input.subarray(8, length + 8); input = input.subarray(length + 8);
        if (opcode === 3) { socket.write(frame(4, body)); continue; }
        if (opcode === 4) continue;
        if (opcode === 2 || opcode !== 1) { socket.destroy(); return; }
        let message;
        try { message = JSON.parse(body.toString('utf8')); } catch { socket.destroy(); return; }
        if (!message || typeof message !== 'object' || Array.isArray(message)) { socket.destroy(); return; }
        if (message.evt === 'READY') {
          clearTimeout(this.attempt); this.attempt = null;
          this.ready = true; this.sentAt = 0; this.flush();
        } else if (message.nonce === this.pending) {
          this.pending = null;
          clearTimeout(this.attempt); this.attempt = null;
          if (message.evt === 'ERROR') { socket.destroy(); return; }
          this.flush();
        }
      }
    });
  }

  flush() {
    if (!this.ready || this.pending || this.stopped) return;
    const serialized = JSON.stringify(this.activity);
    if (serialized === this.last) return;
    const delay = this.interval - (Date.now() - this.sentAt);
    if (delay > 0) {
      if (!this.timer) this.timer = setTimeout(() => { this.timer = null; this.flush(); }, delay);
      return;
    }
    this.pending = String(++this.nonce); this.last = serialized; this.sentAt = Date.now();
    this.socket.write(frame(1, {cmd: 'SET_ACTIVITY', args: {pid: this.pid, activity: this.activity}, nonce: this.pending}));
    this.attempt = setTimeout(() => this.socket?.destroy(), this.timeout * 3);
  }

  stop() {
    if (this.stopped) return;
    this.stopped = true; clearTimeout(this.timer); clearTimeout(this.attempt);
    // Clearing bypasses the update interval, including when sharing is disabled.
    if (this.ready) this.socket.end(frame(1, {cmd: 'SET_ACTIVITY', args: {pid: this.pid, activity: null}, nonce: String(++this.nonce)}));
    else this.socket?.destroy();
    const socket = this.socket;
    setTimeout(() => socket?.destroy(), 250).unref();
  }
}

function main() {
  const [clientId, rawPid] = process.argv.slice(2);
  const pid = Number(rawPid);
  if (!/^[0-9]{17,20}$/.test(clientId || '') || !Number.isSafeInteger(pid) || pid <= 0) { process.exitCode = 1; return; }
  const presence = new DiscordPresence(clientId, pid);
  const lines = readline.createInterface({input: process.stdin, terminal: false});
  lines.on('line', line => {
    if (Buffer.byteLength(line) > 8192) return;
    try {
      const activity = JSON.parse(line);
      if (activity && typeof activity === 'object' && !Array.isArray(activity)) presence.update(activity);
    } catch {} // Ignore an incomplete/invalid update; keep the last valid one.
  });
  lines.on('close', () => presence.stop());
  for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => { lines.close(); process.stdin.destroy(); presence.stop(); });
  // A crashed parent closes stdin. Also guard against a runtime retaining it.
  const parent = setInterval(() => {
    try { process.kill(pid, 0); } catch { lines.close(); process.stdin.destroy(); presence.stop(); }
  }, 5000);
  parent.unref();
}

if (require.main === module) main();
module.exports = {DiscordPresence, frame, ipcPaths};
