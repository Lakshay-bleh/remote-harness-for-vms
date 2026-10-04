import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { ANIMALS, DEFAULT_ANIMAL, isAnimal } from './animals';
import { COMPANION_KEY, parseCompanion } from './companion';
import { H, paletteFor, SCENES, sceneFrames, W } from './sprites';

for (const animal of ANIMALS.map((a) => a.id)) describe(`the ${animal}`, () => {
  const PALETTE = paletteFor(animal);
  for (const scene of SCENES) {
    describe(scene, () => {
      const { frames, frameMs } = sceneFrames(scene, animal);

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

describe('the companions', () => {
  it('are the six that were promised, each with a name', () => {
    assert.deepEqual(ANIMALS.map((a) => [a.id, a.name]), [['dog', 'Shiro'], ['unicorn', 'Stacy'], ['pigeon', 'Riti'], ['hamster', 'Bubbly'], ['cat', 'Tom'], ['elephant', 'Jumbo']]);
  });
  it('are each drawn differently from the others', () => {
    for (const scene of SCENES) {
      const pictures = ANIMALS.map((a) => sceneFrames(scene, a.id).frames[0].join(''));
      assert.equal(new Set(pictures).size, ANIMALS.length, `two animals look the same in ${scene}`);
    }
  });
  it('keep the dog as the default, and ignore a choice that is not an animal', () => {
    assert.equal(DEFAULT_ANIMAL, 'dog');
    assert.equal(parseCompanion('unicorn'), 'unicorn');
    assert.equal(parseCompanion('dragon'), 'dog');
    assert.equal(parseCompanion(null), 'dog');
    assert.equal(isAnimal('cat'), true);
    assert.equal(isAnimal('Cat'), false);
    assert.match(COMPANION_KEY, /companion/);
  });
});
