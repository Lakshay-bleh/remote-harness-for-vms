import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { describeGroupRequest, findGroup, sortGroups } from './permissions';

const groups = [
  { id: 'os', label: 'Open apps and websites', about: 'x', enabled: false },
  { id: 'docker', label: 'Docker', about: 'y', enabled: true },
  { id: 'shell', label: 'Terminal and commands', about: 'z', enabled: false },
];

describe('describeGroupRequest (what to tell the person after they ask)', () => {
  it('says where the question appeared and what to do with it', () => {
    const m = describeGroupRequest('asked', 'Open apps and websites');
    assert.match(m, /Escanor Desktop/);
    assert.match(m, /Open apps and websites/);
    assert.match(m, /Allow|allow|OK/);
  });
  it('tells you to open Escanor Desktop when it has no window to ask in', () => {
    assert.match(describeGroupRequest('unavailable', 'Docker'), /Open Escanor Desktop/);
  });
  it('covers the other answers plainly', () => {
    assert.match(describeGroupRequest('already_on', 'Docker'), /already/i);
    assert.match(describeGroupRequest('busy', 'Docker'), /already (been )?asked|waiting/i);
    assert.match(describeGroupRequest('unknown', 'Docker'), /does not recognise|not recognise|update/i);
  });
});

describe('findGroup', () => {
  it('matches a label exactly, ignoring case and the curly or straight quotes', () => {
    assert.equal(findGroup(groups, 'open apps and websites')?.id, 'os');
    assert.equal(findGroup(groups, ' Docker ')?.id, 'docker');
    assert.equal(findGroup(groups, 'Nothing like it'), undefined);
  });
});

describe('sortGroups', () => {
  it('puts what is switched off first, since that is what the person came to fix, then by name', () => {
    assert.deepEqual(sortGroups(groups).map((g) => g.id), ['os', 'shell', 'docker']);
  });
  it('does not change the list it is given', () => {
    const copy = [...groups];
    sortGroups(groups);
    assert.deepEqual(groups, copy);
  });
});
