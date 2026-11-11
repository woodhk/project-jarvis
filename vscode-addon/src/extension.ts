import * as fs from 'fs';
import * as net from 'net';
import * as os from 'os';
import * as path from 'path';
import * as vscode from 'vscode';
import { Env, handle, TerminalInfo } from './protocol';

// Each VS Code window runs its own copy of this add-on and listens on its own local socket:
//   ~/Library/Application Support/Jarvis/vscode/<process id>.sock
// Messages are one JSON object per line. Nothing leaves this Mac.

let server: net.Server | undefined;
let socketPath: string | undefined;

const env: Env = {
  focused: () => vscode.window.state.focused,
  // The saved workspace file comes first when there is one: opening it (not one of its folders) is what brings
  // this window forward.
  folders: () => {
    const folders = (vscode.workspace.workspaceFolders ?? []).filter(f => f.uri.scheme === 'file').map(f => f.uri.fsPath);
    const workspace = vscode.workspace.workspaceFile;
    return workspace && workspace.scheme === 'file' ? [workspace.fsPath, ...folders] : folders;
  },
  terminals: async () => {
    const found: TerminalInfo[] = [];
    for (const terminal of vscode.window.terminals) {
      const pid = await terminal.processId;
      if (pid !== undefined) {
        found.push({ shellPid: pid, name: terminal.name, show: () => terminal.show(false) });
      }
    }
    return found;
  },
  activeShellPid: async () => vscode.window.activeTerminal?.processId,
};

function cleanUp(): void {
  server?.close();
  server = undefined;
  if (socketPath) {
    try { fs.unlinkSync(socketPath); } catch { /* already gone */ }
  }
}

export function activate(context: vscode.ExtensionContext): void {
  const dir = path.join(os.homedir(), 'Library', 'Application Support', 'Jarvis', 'vscode');
  fs.mkdirSync(dir, { recursive: true });
  socketPath = path.join(dir, `${process.pid}.sock`);
  try { fs.unlinkSync(socketPath); } catch { /* no stale socket */ }

  server = net.createServer(socket => {
    let buffer = '';
    let busy = Promise.resolve();
    socket.setEncoding('utf8');
    socket.on('error', () => { /* the other side went away */ });
    socket.on('data', (chunk: string) => {
      buffer += chunk;
      let end: number;
      while ((end = buffer.indexOf('\n')) >= 0) {
        const line = buffer.slice(0, end).trim();
        buffer = buffer.slice(end + 1);
        if (!line) { continue; }
        busy = busy.then(async () => {
          let reply: object;
          try {
            reply = await handle(JSON.parse(line), env);
          } catch {
            reply = { ok: false, error: 'unknown command' };
          }
          socket.write(JSON.stringify(reply) + '\n');
        });
      }
    });
  });
  server.on('error', () => { /* Jarvis reports a missing add-on in its setup window */ });
  server.listen(socketPath);
  context.subscriptions.push({ dispose: cleanUp });
}

export function deactivate(): void {
  cleanUp();
}
