// Runs the launcher's real install/boot-link/remove commands against a fake TV filesystem.   Run: npm test
import {build} from 'esbuild';
import {execSync, spawn} from 'child_process';
import {existsSync, mkdirSync, readFileSync, writeFileSync, mkdtempSync, rmSync} from 'fs';
import {tmpdir} from 'os';
import {join} from 'path';

const out = new URL('../node_modules/.cache-homehookcmd-test.mjs', import.meta.url).pathname;
await build({entryPoints: [new URL('../src/lib/homehookcmd.ts', import.meta.url).pathname], bundle: true, format: 'esm', outfile: out, platform: 'node', logLevel: 'error'});
const h = await import(out);
const here = (p) => new URL(p, import.meta.url).pathname;
let fail = 0;
const eq = (a, b, m) => { const ok = a === b; if (!ok) fail++; console.log(ok ? 'ok  ' : 'FAIL', m, ok ? '' : `(${a} != ${b})`); };

eq([h.parseHookResult('applied\n[exit 0]'), h.parseHookResult('x\nlauncher-missing\n[exit 2]'), h.parseHookResult('stopped\n[exit 0]'), h.parseHookResult('garbage'), h.parseHookResult('')].join(','), 'applied,launcher-missing,stopped,failed,failed', 'the result word is found in the apply output');
eq(h.utf8Base64('plain ascii'), btoa('plain ascii'), 'ASCII text is encoded as before');
eq(Buffer.from(h.utf8Base64('Домашний экран загружается…'), 'base64').toString('utf8'), 'Домашний экран загружается…', 'non-ASCII text is carried as UTF-8');
eq([h.parseExit('hello\n[exit 0]'), h.parseExit('boom\n[exit 127]\n'), h.parseExit('no status')].map(String).join(','), '0,127,null', 'exit codes are read');
eq(h.lastLine('base64: invalid option -- d\n[exit 1]'), 'base64: invalid option -- d', 'the last message is what the user is told');
const st = (o) => JSON.stringify(h.parseHookStatus(o));
eq([st('running\nlinked\n'), st('linked\n'), st('running\n'), st(''), st('linked\nstopped\n')].join(' '), '{"running":true,"linked":true,"stopped":false} {"running":false,"linked":true,"stopped":false} {"running":true,"linked":false,"stopped":false} {"running":false,"linked":false,"stopped":false} {"running":false,"linked":true,"stopped":true}', 'status output is read');

const root = mkdtempSync(join(tmpdir(), 'fake-tv-'));
const fake = (cmd) => cmd.split('/media/developer').join(root + '/media/developer').split('/var/lib/webosbrew').join(root + '/var/lib/webosbrew').split('/tmp/launcher').join(root + '/tmp/launcher');
const env = () => ({...process.env, DRY_RUN: '1', LOG: root + '/tmp/log', APP_QML: root + '/usr/palm/qml', HOOK: root + '/media/developer/launcher-homehook', LAUNCHER: root + '/media/developer/apps/usr/palm/applications/com.hearthng.launcher', PIDFILE: root + '/tmp/launcher-homehook-watch.pid', GUARD_PIDFILE: root + '/tmp/launcher-homehook-guard.pid', ALLOW: root + '/tmp/launcher-allow-stock-home'});
const run = (cmd) => execSync(fake(cmd), {shell: '/bin/sh', encoding: 'utf8', env: env()});
const sh = (cmd) => { try { return run(cmd); } catch (e) { return String(e.stdout || ''); } };
mkdirSync(root + '/tmp', {recursive: true});
mkdirSync(root + '/usr/palm/qml', {recursive: true});
mkdirSync(root + '/var/lib/webosbrew/init.d', {recursive: true});
const files = {watchSh: readFileSync(here('../src/homehook/watch.sh'), 'utf8'), applySh: readFileSync(here('../src/homehook/apply.sh'), 'utf8'), stockSh: readFileSync(here('../src/homehook/stock.sh'), 'utf8'), diagnoseSh: readFileSync(here('../src/homehook/diagnose.sh'), 'utf8'), guardSh: readFileSync(here('../src/homehook/guard.sh'), 'utf8'), stopSh: readFileSync(here('../src/homehook/stop.sh'), 'utf8')};
const hook = root + '/media/developer/launcher-homehook';
const link = root + '/var/lib/webosbrew/init.d/48-launcher-homehook';
const launcherDir = root + '/media/developer/apps/usr/palm/applications/com.hearthng.launcher';

const runInstall = (options) => {
  let output = '';
  const steps = h.installSteps(files, options);
  for (let i = 0; i < steps.length; i++) {
    output = sh(h.withStatus(steps[i].command));
    if (i < steps.length - 1 && h.parseExit(output) !== 0) return {output, failedStep: steps[i].name};
  }
  return {output, failedStep: null};
};

// launcher not installed yet -> refused
eq(h.parseHookResult(runInstall().output), 'launcher-missing', 'install is refused while the launcher is not installed');
mkdirSync(launcherDir, {recursive: true});
writeFileSync(launcherDir + '/appinfo.json', '{}');

// install (the boot link is always added)
eq(h.parseHookResult(runInstall().output), 'applied', 'install works');
eq(h.SCRIPT_NAMES.every((f) => readFileSync(hook + '/' + f, 'utf8') === files[f.replace('.sh', 'Sh')]), true, 'all six scripts were written byte for byte (UTF-8 included)');
eq(/[^\x00-\x7f]/.test(files.watchSh), true, 'watch.sh does carry non-ASCII text (the Russian notifications)');
eq(readFileSync(hook + '/version', 'utf8').trim(), h.HOOK_VERSION, 'the version was recorded');
eq(sh(h.VERSION_COMMAND).trim(), h.HOOK_VERSION, 'the launcher can read the installed version back');
eq(existsSync(link), true, 'the boot link exists');
eq(st(sh(h.STATUS_COMMAND)), '{"running":false,"linked":true,"stopped":false}', 'status: linked (the watcher is not started in a dry run)');
eq(h.parseHookResult(sh(h.APPLY_COMMAND)), 'applied', 'applying again works');

// the emergency exit (stop.sh): apply starts nothing, an update keeps it, switching the helper on undoes it
writeFileSync(hook + '/stopped', '');
eq(h.parseHookResult(sh(h.APPLY_COMMAND)), 'stopped', 'with the emergency exit on, apply says stopped');
eq(st(sh(h.STATUS_COMMAND)), '{"running":false,"linked":true,"stopped":true}', 'status: stopped');
eq(h.parseHookResult(runInstall().output), 'stopped', 'rewriting the files (an update) keeps the emergency exit');
eq(existsSync(hook + '/stopped'), true, 'and its file');
eq(h.parseHookResult(runInstall({resume: true}).output), 'applied', 'switching the helper on undoes the emergency exit');
eq(existsSync(hook + '/stopped'), false, 'and removes its file');

// installing again keeps the link, and it is added if it was missing (an older install, or one removed by hand)
sh(`rm -f '${link}'`);
eq(h.parseHookResult(runInstall().output), 'applied', 'installing again works');
eq(existsSync(link), true, 'and puts the boot link back if it was missing');

// stock home request
runInstall();
sh(h.STOCK_COMMAND);
eq(existsSync(root + '/tmp/launcher-allow-stock-home'), true, 'the LG Home tile makes the watcher stand down');

// stopping an older watcher: a real process whose pid is in the pid file
const child = spawn('sleep', ['60'], {stdio: 'ignore', detached: true}); child.unref();
writeFileSync(root + '/tmp/launcher-homehook-watch.pid', String(child.pid));
const stopStep = h.installSteps(files).find((s) => s.name === 'stop an older watcher');
sh(h.withStatus(stopStep.command));
await new Promise((r) => setTimeout(r, 300));
let alive = true; try { process.kill(child.pid, 0); } catch { alive = false; }
eq([alive, existsSync(root + '/tmp/launcher-homehook-watch.pid')].join(','), 'false,false', 'an older watcher is stopped and its pid file removed');
const guardChild = spawn('sleep', ['60'], {stdio: 'ignore', detached: true}); guardChild.unref();
writeFileSync(root + '/tmp/launcher-homehook-guard.pid', String(guardChild.pid));
sh(h.withStatus(stopStep.command));
await new Promise((r) => setTimeout(r, 300));
let guardAlive = true; try { process.kill(guardChild.pid, 0); } catch { guardAlive = false; }
eq([guardAlive, existsSync(root + '/tmp/launcher-homehook-guard.pid')].join(','), 'false,false', 'its guard is stopped too, and its pid file removed');

// a watcher that ignores a polite stop (as a shell busy with a long command does) is still stopped
const stubborn = spawn('sh', ['-c', 'trap : TERM; while true; do sleep 1; done'], {stdio: 'ignore', detached: true}); stubborn.unref();
writeFileSync(root + '/tmp/launcher-homehook-watch.pid', String(stubborn.pid));
sh(h.withStatus(stopStep.command));
await new Promise((r) => setTimeout(r, 400));
let stubbornAlive = true; try { process.kill(stubborn.pid, 0); } catch { stubbornAlive = false; }
eq(stubbornAlive, false, 'a watcher that ignores a polite stop is stopped for sure');
// a watcher whose pid file was lost is found by its command line
const lost = spawn('bash', ['-c', 'exec -a "sh /media/developer/launcher-homehook/watch.sh" sleep 60'], {stdio: 'ignore', detached: true}); lost.unref();
await new Promise((r) => setTimeout(r, 300));
sh(h.withStatus(stopStep.command));
await new Promise((r) => setTimeout(r, 400));
let lostAlive = true; try { process.kill(lost.pid, 0); } catch { lostAlive = false; }
eq(lostAlive, false, 'a watcher with no pid file is found by its command line and stopped');
// the files are replaced by moving, never written in place
eq(h.installSteps(files).filter((st) => /watch\.sh/.test(st.command) && />+ '/.test(st.command)).every((st) => /watch\.sh\.new/.test(st.command)), true, 'watch.sh is written under a temporary name first');
eq(existsSync(hook + '/watch.sh.new') || existsSync(hook + '/apply.sh.new'), false, 'no temporary files are left after an install');

// removal
sh(h.REMOVE_COMMAND);
eq([existsSync(hook), existsSync(link), existsSync(root + '/tmp/launcher-allow-stock-home')].join(','), 'false,false,false', 'remove deletes the folder, the boot link and the stand-down flag');
eq(st(sh(h.STATUS_COMMAND)), '{"running":false,"linked":false,"stopped":false}', 'status: off after removal');
eq(st('linked\nflutterhome\n'), '{"running":false,"linked":true,"stopped":false,"frozenHome":true}', 'status: LG Home is a Flutter app (frozen by the helper)');
eq(h.STATUS_COMMAND.includes(h.FLUTTER_HOME_DIR), true, 'status command looks for LG Home\'s Flutter files');
eq(h.REMOVE_COMMAND.includes("pkill -CONT -f '[f]lutter-client -i com\\.webos\\.app\\.home([^A-Za-z0-9._-]|$)'"), true, 'removal unfreezes LG Home (exact process pattern)');
eq(h.REMOVE_COMMAND.indexOf('pkill -CONT') > h.REMOVE_COMMAND.indexOf('[l]auncher-homehook/watch.sh'), true, 'only after the watcher is stopped');
eq(h.parseHookResult(sh(h.APPLY_COMMAND)), 'files-missing', 'apply after removal does nothing');

// the commands themselves
const steps = h.installSteps(files);
eq(steps.some((s) => s.command.includes(files.watchSh.slice(0, 60))), false, 'file contents are carried as base64, never raw');
eq(Math.max(...steps.map((s) => s.command.length)) < 4300, true, `every install step is a small command (largest ${Math.max(...steps.map((s) => s.command.length))} characters)`);
// a failing step says which one and why
mkdirSync(root + '/media/developer', {recursive: true});
writeFileSync(hook, 'a file where the folder should be');
const broken = runInstall();
eq(broken.failedStep, 'create the folder', 'a failing step is named');
eq(h.lastLine(broken.output).length > 0, true, 'and the TV\'s own error text comes back with it');
rmSync(hook, {force: true});
rmSync(root, {recursive: true, force: true});
process.exit(fail ? 1 : 0);
