// A process whose command line is exactly `name`, for the tests of commands that find a process by its command line.
// `exec -a NAME sleep 60` is not enough: where sleep is a #! script (coreutils built as one program, as on Amazon
// Linux 2023) the kernel puts the interpreter in front and NAME never reaches /proc/<pid>/cmdline, so nothing matches.
// bash is a real program: started with argv0 it keeps NAME, and with an open pipe as its input it waits for commands
// until it is stopped or the test ends (the pipe closes and it leaves).
import {spawn} from 'child_process';
import {existsSync, readFileSync} from 'fs';
const cmdline = (pid) => { try { return readFileSync(`/proc/${pid}/cmdline`, 'utf8'); } catch { return null; } };
export const startLookalike = async (name) => {
  const p = spawn('bash', [], {argv0: name, stdio: ['pipe', 'ignore', 'ignore'], detached: true});
  p.unref(); p.stdin.unref();
  if (!existsSync('/proc/self/cmdline')) return p;   // no /proc: nothing to check here
  for (let i = 0; i < 50; i++) {
    if (cmdline(p.pid) === name + '\0') return p;
    await new Promise((r) => setTimeout(r, 20));
  }
  throw new Error(`test setup: a process named "${name}" could not be made (its command line reads ${JSON.stringify(cmdline(p.pid))})`);
};
