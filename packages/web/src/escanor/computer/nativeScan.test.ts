import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { classifyScanError, firstQr } from './nativeScan';

describe('classifyScanError', () => {
  it('treats the person closing the scanner as a cancel, not an error', () => {
    for (const m of ['scan canceled.', 'Scan cancelled', 'User canceled', 'SCAN_CANCELED']) assert.equal(classifyScanError(new Error(m)), 'cancelled', m);
  });

  it('recognises a phone that has no Google scanner module', () => {
    for (const m of ['Google Barcode Scanner Module is not available.', 'not implemented on web', 'ModuleNotInstalled', 'Google Play services are not available']) assert.equal(classifyScanError(new Error(m)), 'unavailable', m);
  });

  it('calls anything else a failure, whatever shape it comes in', () => {
    for (const e of [new Error('boom'), 'plain string', null, undefined, { code: 7 }]) assert.equal(classifyScanError(e), 'failed');
  });
});

describe('firstQr', () => {
  it('takes the first readable value, ignoring empty ones', () => {
    assert.equal(firstQr({ barcodes: [{ rawValue: '' }, { rawValue: 'hello' }, { rawValue: 'later' }] }), 'hello');
  });

  it('returns null when nothing was read', () => {
    for (const r of [{ barcodes: [] }, { barcodes: [{ rawValue: '' }, {}] }, {}, null, undefined]) assert.equal(firstQr(r as never), null);
  });
});
