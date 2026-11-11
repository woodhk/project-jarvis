// The messages between Jarvis and this add-on. This file does not import 'vscode', so it runs under `node --test`.

export interface TerminalInfo {
  shellPid: number;
  name: string;
  show(): void;
}

/** What the protocol needs from the VS Code window it runs in. */
export interface Env {
  focused(): boolean;
  folders(): string[];
  terminals(): Promise<TerminalInfo[]>;
  activeShellPid(): Promise<number | undefined>;
}

export type Request = { cmd: 'state' } | { cmd: 'focus'; shellPid: number };

async function state(env: Env): Promise<object> {
  const terminals = await env.terminals();
  return {
    focused: env.focused(),
    folders: env.folders(),
    terminals: terminals.map(t => ({ shellPid: t.shellPid, name: t.name })),
    activeShellPid: (await env.activeShellPid()) ?? null,
  };
}

/**
 * `state` describes this window. `focus` shows the terminal whose shell has the given process id, if this window
 * owns it, and answers `{ ok: true, ...state }`; any other window answers `{ ok: false }`.
 */
export async function handle(request: Request, env: Env): Promise<object> {
  const cmd = (request as { cmd?: unknown } | null)?.cmd;
  if (cmd === 'state') {
    return state(env);
  }
  if (cmd === 'focus' && typeof (request as { shellPid?: unknown }).shellPid === 'number') {
    const wanted = (request as { shellPid: number }).shellPid;
    const terminal = (await env.terminals()).find(t => t.shellPid === wanted);
    if (!terminal) {
      return { ok: false };
    }
    terminal.show();
    return { ok: true, ...(await state(env)) };
  }
  return { ok: false, error: 'unknown command' };
}
