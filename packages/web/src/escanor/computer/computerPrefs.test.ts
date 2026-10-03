import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { applyRoute, displayName, parseComputerPrefs, cleanName } from './computerPrefs';

const computer = { id: 'd1', name: 'Work Laptop', key: 'k', lan: ['192.168.1.5:47625'], agentId: 'a1', pairedAt: '2026-10-01T00:00:00Z' };

describe('parseComputerPrefs', () => {
  it('gives plain defaults for nothing, damage or junk', () => {
    for (const raw of [null, '', '{bad', '[]', '"x"', '5']) assert.deepEqual(parseComputerPrefs(raw), { alias: '', route: 'auto' }, String(raw));
  });
  it('keeps a valid alias and route, and ignores wrong types field by field', () => {
    assert.deepEqual(parseComputerPrefs(JSON.stringify({ alias: 'Home PC', route: 'cloud' })), { alias: 'Home PC', route: 'cloud' });
    assert.deepEqual(parseComputerPrefs(JSON.stringify({ alias: 5, route: 'teleport' })), { alias: '', route: 'auto' });
  });
});

describe('cleanName', () => {
  it('trims, collapses spaces and limits the length', () => {
    assert.equal(cleanName('  My   laptop  '), 'My laptop');
    assert.equal(cleanName('x'.repeat(100)).length, 40);
    assert.equal(cleanName('   '), '');
  });
  it('drops control characters', () => {
    assert.equal(cleanName('Lap\u0000top\n'), 'Laptop');
  });
});

describe('displayName', () => {
  it('uses the chosen name, else the name the computer gave itself', () => {
    assert.equal(displayName(computer, { alias: 'Desk', route: 'auto' }), 'Desk');
    assert.equal(displayName(computer, { alias: '', route: 'auto' }), 'Work Laptop');
  });
});

describe('applyRoute (the connection preference)', () => {
  it('automatic keeps both routes', () => {
    assert.deepEqual(applyRoute(computer, 'auto'), { computer, cloud: true });
  });
  it('cloud only forgets the Wi-Fi addresses for this connection', () => {
    const r = applyRoute(computer, 'cloud');
    assert.deepEqual(r.computer.lan, []);
    assert.equal(r.cloud, true);
    assert.deepEqual(computer.lan, ['192.168.1.5:47625']); // the stored computer is untouched
  });
  it('Wi-Fi only turns the cloud route off', () => {
    assert.equal(applyRoute(computer, 'lan').cloud, false);
    assert.deepEqual(applyRoute(computer, 'lan').computer.lan, computer.lan);
  });
});
