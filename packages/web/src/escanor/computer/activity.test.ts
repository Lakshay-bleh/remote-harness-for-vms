import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { activityLabel } from './activityLabel';

describe('activityLabel', () => {
  it('names the common actions in plain English', () => {
    assert.equal(activityLabel('os.open_url'), 'Opened a website');
    assert.equal(activityLabel('os.open_app'), 'Opened an app');
    assert.equal(activityLabel('system.stats'), 'Checked how busy it is');
    assert.equal(activityLabel('shell.exec'), 'Ran a command');
  });
  it('turns any other id into something readable, never the raw id', () => {
    assert.equal(activityLabel('docker.restart_container'), 'Docker: restart container');
    assert.equal(activityLabel('weird'), 'Weird');
    assert.equal(activityLabel(''), 'Something');
  });
});
