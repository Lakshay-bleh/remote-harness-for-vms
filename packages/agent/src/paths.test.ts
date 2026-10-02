import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, realpathSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { resolveInside, workspaceRootFrom, isBroadRoot } from './paths.js';

const mk = () => {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'paths-root-')));
  const outside = realpathSync(mkdtempSync(join(tmpdir(), 'paths-outside-')));
  return { root, outside };
};

describe('resolveInside', () => {
  it('allows the root, nested dirs, not-yet-existing dirs, and directories named "..foo"', () => {
    const { root } = mk();
    mkdirSync(join(root, 'app'));
    mkdirSync(join(root, '..foo'));
    assert.equal(resolveInside(root, undefined), root);
    assert.equal(resolveInside(root, 'app'), join(root, 'app'));
    assert.equal(resolveInside(root, 'app/new'), join(root, 'app/new'));
    assert.equal(resolveInside(root, '..foo'), join(root, '..foo'));
  });

  it('falls back to the root for traversal and absolute paths outside it', () => {
    const { root, outside } = mk();
    assert.equal(resolveInside(root, '..'), root);
    assert.equal(resolveInside(root, '../etc'), root);
    assert.equal(resolveInside(root, outside), root);
  });

  it('does not follow a symlink inside the workspace that points outside it', () => {
    const { root, outside } = mk();
    symlinkSync(outside, join(root, 'escape'));
    assert.equal(resolveInside(root, 'escape'), root);
    assert.equal(resolveInside(root, 'escape/sub'), root);
  });

  it('allows a symlink that stays inside the workspace', () => {
    const { root } = mk();
    mkdirSync(join(root, 'real'));
    symlinkSync(join(root, 'real'), join(root, 'alias'));
    assert.equal(resolveInside(root, 'alias'), join(root, 'real'));
  });
});

describe('workspaceRootFrom', () => {
  it('uses WORKSPACE_ROOT, else HOME', () => {
    assert.equal(workspaceRootFrom({ WORKSPACE_ROOT: '/srv/w', HOME: '/home/u' }), '/srv/w');
    assert.equal(workspaceRootFrom({ HOME: '/home/u' }), '/home/u');
  });
  it('refuses to fall back to "/" when nothing is set', () => {
    assert.throws(() => workspaceRootFrom({}), /WORKSPACE_ROOT/);
  });
});

describe('isBroadRoot', () => {
  it('flags / and the home directory itself', () => {
    assert.equal(isBroadRoot('/', '/home/u'), true);
    assert.equal(isBroadRoot('/home/u', '/home/u'), true);
    assert.equal(isBroadRoot('/home/u/projects', '/home/u'), false);
  });
});
