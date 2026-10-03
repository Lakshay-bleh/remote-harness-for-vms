import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { H, PALETTE, SCENES, sceneFrames, W } from './sprites';

describe('the dog', () => {
  for (const scene of SCENES) {
    describe(scene, () => {
      const { frames, frameMs } = sceneFrames(scene);

      it('has every frame the same size, W by H', () => {
        for (const f of frames) {
          assert.equal(f.length, H);
          for (const row of f) assert.equal(row.length, W);
        }
      });

      it('uses only colours it defines', () => {
        for (const f of frames) for (const row of f) for (const c of row) assert.ok(c === '.' || c in PALETTE, `unknown pixel "${c}"`);
      });

      it('moves: it has several frames and they are not all the same', () => {
        assert.ok(frames.length >= 4);
        assert.ok(new Set(frames.map((f) => f.join('\n'))).size >= 3);
        assert.ok(frameMs >= 80 && frameMs <= 600);
      });

      it('is drawn, outlined and not clipped at the edges', () => {
        for (const f of frames) {
          const body = f.join('');
          assert.ok((body.match(/f/g) ?? []).length > 30, 'fur');
          assert.ok((body.match(/o/g) ?? []).length > 20, 'outline');
          // the dog itself (outline pixels) never touches the edge of the picture, where it would be cut off
          for (const [y, row] of f.entries()) {
            if (y === 0 || y === H - 1) assert.ok(!row.includes('o'), `outline on edge row ${y}`);
            assert.notEqual(row[0], 'o', `outline on left edge, row ${y}`);
            assert.notEqual(row[W - 1], 'o', `outline on right edge, row ${y}`);
          }
        }
      });
    });
  }
});
