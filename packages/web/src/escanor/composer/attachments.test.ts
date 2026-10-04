import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { canAdd, classify, clipText, fitWithin, humanSize, inlineText, LIMITS, toApi, UNSUPPORTED, type Attachment } from './attachments';

const att = (name: string, extra: Partial<Attachment> = {}): Attachment => ({ id: name, name, mime: 'text/plain', size: 10, kind: 'text', text: 'hello', ...extra });

describe('classify', () => {
  it('knows photos, PDFs and text or code', () => {
    assert.equal(classify('a.jpg', 'image/jpeg'), 'image');
    assert.equal(classify('a.heic', 'image/heic'), 'image');
    assert.equal(classify('r.pdf', 'application/pdf'), 'pdf');
    assert.equal(classify('r.pdf', ''), 'pdf');
    assert.equal(classify('notes.md', ''), 'text');
    assert.equal(classify('main.py', 'text/x-python'), 'text');
    assert.equal(classify('data', 'application/json'), 'text');
  });
  it('refuses what it cannot read', () => {
    assert.equal(classify('a.docx', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'), null);
    assert.equal(classify('movie.mp4', 'video/mp4'), null);
    assert.equal(classify('a.exe', 'application/octet-stream'), null);
  });
});

describe('canAdd', () => {
  it('says why a file cannot be attached', () => {
    assert.equal(canAdd([], { name: 'a.docx', type: '', size: 1 }), UNSUPPORTED);
    assert.match(canAdd([att('1'), att('2'), att('3'), att('4')], { name: 'x.txt', type: 'text/plain', size: 1 })!, /up to 4/);
    assert.match(canAdd([], { name: 'big.pdf', type: 'application/pdf', size: LIMITS.bytesEach + 1 })!, /too big/);
    assert.match(canAdd([att('a.txt', { size: 5 })], { name: 'a.txt', type: 'text/plain', size: 5 })!, /already attached/);
  });
  it('lets a photo in however big it is, because it is shrunk before sending', () => {
    assert.equal(canAdd([], { name: 'p.jpg', type: 'image/jpeg', size: 30 * 1024 * 1024 }), null);
  });
  it('in a words-only chat, takes only text and code', () => {
    assert.equal(canAdd([], { name: 'a.log', type: '', size: 100 }, 'text'), null);
    assert.match(canAdd([], { name: 'p.jpg', type: 'image/jpeg', size: 100 }, 'text')!, /text and code/);
  });
});

describe('what is sent', () => {
  it('sends the bytes of photos and PDFs and the words of text files, and nothing else', () => {
    const list = [att('a.txt'), att('p.jpg', { kind: 'image', mime: 'image/jpeg', data: 'QUJD', text: undefined, preview: 'data:...' })];
    assert.deepEqual(toApi(list), [{ name: 'a.txt', mime: 'text/plain', kind: 'text', text: 'hello' }, { name: 'p.jpg', mime: 'image/jpeg', kind: 'image', data: 'QUJD' }]);
  });
  it('puts text files into a words-only message, under their names, if it fits', () => {
    assert.equal(inlineText('what is wrong?', [att('err.log', { text: 'boom' })], 100), 'what is wrong?\n\n[err.log]\nboom');
    assert.equal(inlineText('x', [att('big.log', { text: 'a'.repeat(200) })], 100), null);
  });
  it('cuts a long text file and says so', () => {
    assert.deepEqual(clipText('short'), { text: 'short', cut: false });
    const r = clipText('a'.repeat(LIMITS.textChars + 5));
    assert.equal(r.text.length, LIMITS.textChars);
    assert.equal(r.cut, true);
  });
});

describe('fitWithin', () => {
  it('shrinks to the longest side, keeping the shape', () => {
    assert.deepEqual(fitWithin(4000, 2000), { width: 1568, height: 784 });
    assert.deepEqual(fitWithin(2000, 4000), { width: 784, height: 1568 });
  });
  it('never enlarges', () => assert.deepEqual(fitWithin(800, 600), { width: 800, height: 600 }));
});

it('humanSize', () => {
  assert.equal(humanSize(900), '900 B');
  assert.equal(humanSize(2048), '2 KB');
  assert.equal(humanSize(5.5 * 1024 * 1024), '5.5 MB');
});
