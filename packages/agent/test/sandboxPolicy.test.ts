import assert from 'node:assert/strict';
import test from 'node:test';
import { commandLeavesSandbox, isSandboxAutoAllowed } from '../src/sandboxPolicy.ts';

const root = '/data/work';
const ok = (tool: string, input: Record<string, unknown> = {}) => isSandboxAutoAllowed(tool, input, { root });

test('local reading and searching never asks', () => {
  for (const tool of ['Read', 'Glob', 'Grep', 'LS', 'TodoWrite', 'Task', 'WebFetch', 'WebSearch']) assert.equal(ok(tool, {}), true, tool);
});

test('editing inside the workspace is free, outside it asks', () => {
  assert.equal(ok('Edit', { file_path: '/data/work/app/main.py' }), true);
  assert.equal(ok('Write', { file_path: 'notes.md' }), true, 'relative to the workspace');
  assert.equal(ok('MultiEdit', { file_path: '/data/work/a/../b.txt' }), true);
  for (const p of ['/etc/passwd', '/data/work/../claude/settings.json', '../outside', '/data/home/.bashrc', '']) assert.equal(ok('Edit', { file_path: p }), false, p);
  assert.equal(ok('Write', {}), false, 'no path, no guess');
  assert.equal(ok('NotebookEdit', { notebook_path: '/data/work/x.ipynb' }), true);
});

test('everyday shell work inside the sandbox runs without a card', () => {
  for (const c of ['ls -la', 'pytest -q', 'npm test && npm run build', 'git status', 'git diff', 'git checkout -b fix/login', 'git add -A && git commit -m "fix"', 'python manage.py test', 'cat logs/app.log | grep ERROR', 'curl -s https://example.com/health', 'curl -sS -H "Accept: json" https://api.example.com/x', 'pip install requests', 'git log --oneline -5']) {
    assert.equal(ok('Bash', { command: c }), true, c);
  }
});

test('publishing work or leaving the sandbox asks', () => {
  for (const c of [
    'git push origin fix/login', 'git push', 'cd repo && git push -u origin HEAD', 'npm test; git push origin main', 'git -C repo push', 'git commit -m x && git push --force',
    'gh pr create --title x', 'gh api repos/x/y -X DELETE', 'npm publish', 'twine upload dist/*', 'docker run -it ubuntu', 'kubectl delete pod x', 'sudo apt install x', 'ssh host ls', 'scp a b:/tmp',
    'curl -X POST https://api.example.com -d "{}"', 'curl --request DELETE https://x', 'curl -d x https://x', 'wget --post-data=x https://x', 'git remote add evil https://evil.example/x.git', 'git remote set-url origin https://evil',
  ]) {
    assert.equal(ok('Bash', { command: c }), false, c);
  }
  assert.equal(commandLeavesSandbox('git status'), false);
});

test('an empty or non-string command is not blessed', () => {
  assert.equal(ok('Bash', { command: '' }), false);
  assert.equal(ok('Bash', {}), false);
  assert.equal(ok('Bash', { command: 42 }), false);
});

test('MCP and unknown tools are not decided here', () => {
  assert.equal(ok('mcp__escanor__escanor_invoke', { tool_id: 'github.list_repos' }), false);
  assert.equal(ok('SomethingNew', {}), false);
});
