import { test } from 'node:test';
import assert from 'node:assert/strict';
import { handle, Env } from '../src/protocol';

function makeEnv(): { env: Env; shown: number[] } {
  const shown: number[] = [];
  const env: Env = {
    focused: () => true,
    folders: () => ['/work/shop'],
    terminals: async () => [
      { shellPid: 4242, name: 'zsh', show: () => { shown.push(4242); } },
      { shellPid: 4300, name: 'zsh', show: () => { shown.push(4300); } },
    ],
    activeShellPid: async () => 4242,
  };
  return { env, shown };
}

test('state lists terminals and the active one', async () => {
  const { env } = makeEnv();
  assert.deepEqual(await handle({ cmd: 'state' }, env), {
    focused: true, folders: ['/work/shop'],
    terminals: [{ shellPid: 4242, name: 'zsh' }, { shellPid: 4300, name: 'zsh' }], activeShellPid: 4242,
  });
});

test('focus shows the owned terminal', async () => {
  const { env, shown } = makeEnv();
  const r: any = await handle({ cmd: 'focus', shellPid: 4300 }, env);
  assert.equal(r.ok, true);
  assert.deepEqual(r.folders, ['/work/shop']);
  assert.deepEqual(shown, [4300]);
});

test('focus on a terminal of another window is refused', async () => {
  const { env, shown } = makeEnv();
  assert.deepEqual(await handle({ cmd: 'focus', shellPid: 9 }, env), { ok: false });
  assert.deepEqual(shown, []);
});

test('unknown commands are refused', async () => {
  const { env } = makeEnv();
  assert.deepEqual(await handle({ cmd: 'nope' } as any, env), { ok: false, error: 'unknown command' });
  assert.deepEqual(await handle(null as any, env), { ok: false, error: 'unknown command' });
  assert.deepEqual(await handle({ cmd: 'focus', shellPid: 'x' } as any, env), { ok: false, error: 'unknown command' });
});

test('a window with no active terminal says so', async () => {
  const { env } = makeEnv();
  env.activeShellPid = async () => undefined;
  const r: any = await handle({ cmd: 'state' }, env);
  assert.equal(r.activeShellPid, null);
});
