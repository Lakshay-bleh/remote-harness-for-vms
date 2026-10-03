import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { hubUrlProblem } from './api';

describe('hubUrlProblem', () => {
  it('requires https in the phone app, because plain http is allowed there only for a computer on the local network', () => {
    assert.equal(hubUrlProblem('https://hub.example.com', true), null);
    for (const bad of ['http://hub.example.com', 'http://192.168.1.5:8787', 'hub.example.com', 'ftp://x']) assert.ok(hubUrlProblem(bad, true), bad);
  });
  it('asks nothing of a browser, where the hub serves the page itself, or of an empty address', () => {
    assert.equal(hubUrlProblem('http://localhost:8787', false), null);
    assert.equal(hubUrlProblem('', true), null);
  });
});
