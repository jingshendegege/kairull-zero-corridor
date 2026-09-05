import { mkdirSync, existsSync, copyFileSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const tools = resolve(root, '.build-tools');
const version = '4.7.2';
const base = `https://github.com/godotengine/godot-builds/releases/download/${version}-stable`;
const windows = process.platform === 'win32';
function run(command, args, options = {}) {
  const result = spawnSync(command, args, { cwd: root, stdio: 'inherit', ...options });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} failed (${result.status})`);
}
function download(name) {
  const path = resolve(tools, name);
  if (!existsSync(path)) run(windows ? 'curl.exe' : 'curl', ['-fL', '--retry', '3', `${base}/${name}`, '-o', path]);
  return path;
}
mkdirSync(tools, { recursive: true });
mkdirSync(resolve(root, 'dist'), { recursive: true });
const template = resolve(tools, 'web_nothreads_release.zip');
if (!existsSync(template)) {
  if (windows) throw new Error('Install the official web_nothreads_release.zip in .build-tools before building on Windows.');
  const archive = download(`Godot_v${version}-stable_export_templates.tpz`);
  run('unzip', ['-jo', archive, 'templates/web_nothreads_release.zip', '-d', tools]);
}
let godot = process.env.GODOT_BIN;
if (!godot) {
  if (windows) throw new Error('Set GODOT_BIN to the official Godot 4.7.2 console executable.');
  godot = resolve(tools, `Godot_v${version}-stable_linux.x86_64`);
  if (!existsSync(godot)) {
    const archive = download(`Godot_v${version}-stable_linux.x86_64.zip`);
    run('unzip', ['-o', archive, '-d', tools]);
    run('chmod', ['+x', godot]);
  }
}
run(godot, ['--headless', '--path', resolve(root, 'godot'), '--editor', '--import']);
run(godot, ['--headless', '--path', resolve(root, 'godot'), '--export-release', 'Web', resolve(root, 'dist/index.html')]);
copyFileSync(resolve(root, 'web/vibehub-bridge.js'), resolve(root, 'dist/vibehub-bridge.js'));
copyFileSync(resolve(root, 'web/audio-unlock.js'), resolve(root, 'dist/audio-unlock.js'));
const html = readFileSync(resolve(root, 'dist/index.html'), 'utf8');
if (!html.includes('https://vibe.lumigrav.space/sdk/v3/vibehub.js')) throw new Error('Missing VibeHub SDK');
if (!html.includes('vibehub-bridge.js')) throw new Error('Missing VibeHub authentication UI');
for (const name of readdirSync(resolve(root, 'dist'), { recursive: true })) {
  const file = resolve(root, 'dist', name);
  if (statSync(file).isFile() && statSync(file).size > 100 * 1024 * 1024) {
    throw new Error(`VibeHub single-file limit exceeded: ${name}`);
  }
}
console.log('Web export ready: dist/index.html');
