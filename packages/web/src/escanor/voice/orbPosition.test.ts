import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { DEFAULT_ORB, movedFar, orbCss, ORB_MARGIN, ORB_SIZE, parseOrb, posFromPoint } from './orbPosition';

const view = { width: 400, height: 800, insetTop: 40, insetBottom: 20 };

describe('the voice button position', () => {
  it('turns a point on the screen into a fraction of the free space', () => {
    const topLeft = posFromPoint(ORB_SIZE / 2 + ORB_MARGIN, view.insetTop + ORB_SIZE / 2 + ORB_MARGIN, view);
    assert.deepEqual(topLeft, { x: 0, y: 0 });
    const bottomRight = posFromPoint(view.width - ORB_SIZE / 2 - ORB_MARGIN, view.height - view.insetBottom - ORB_SIZE / 2 - ORB_MARGIN, view);
    assert.deepEqual(bottomRight, { x: 1, y: 1 });
    const mid = posFromPoint(view.width / 2, (view.height + view.insetTop - view.insetBottom) / 2, view);
    assert.ok(Math.abs(mid.x - 0.5) < 0.01 && Math.abs(mid.y - 0.5) < 0.01);
  });

  it('never lets the button leave the screen, wherever it is dragged', () => {
    for (const [x, y] of [[-500, -500], [9999, 9999], [-1, 9999], [9999, -1]]) {
      const p = posFromPoint(x, y, view);
      assert.ok(p.x >= 0 && p.x <= 1 && p.y >= 0 && p.y <= 1, `${x},${y} -> ${JSON.stringify(p)}`);
    }
  });

  it('describes a position in CSS that follows the screen and keeps clear of the status bar', () => {
    const css = orbCss({ x: 1, y: 0 });
    assert.match(css.left, /100vw/);
    assert.match(css.top, /safe-area-inset-top/);
    assert.deepEqual(orbCss({ x: 5, y: -3 }), orbCss({ x: 1, y: 0 }), 'out-of-range values are clamped');
  });

  it('reads a saved position back, and ignores anything else', () => {
    assert.deepEqual(parseOrb('{"x":0.25,"y":0.75}'), { x: 0.25, y: 0.75 });
    assert.deepEqual(parseOrb('{"x":9,"y":-2}'), { x: 1, y: 0 });
    for (const bad of [null, '', 'x', '{}', '{"x":"a","y":1}', '{"x":null,"y":1}', '[1,2]']) assert.equal(parseOrb(bad), null, String(bad));
  });

  it('starts at the right edge, clear of the send button at the bottom', () => {
    assert.equal(DEFAULT_ORB.x, 1);
    assert.ok(DEFAULT_ORB.y < 0.6);
  });

  it('tells a tap from a drag', () => {
    assert.equal(movedFar(3, 3), false);
    assert.equal(movedFar(10, 0), true);
    assert.equal(movedFar(6, 6), true);
  });
});
