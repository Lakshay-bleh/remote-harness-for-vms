import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { ANIMALS, DEFAULT_ANIMAL, isAnimal } from './animals.ts';
import { COMPANION_KEY, parseCompanion } from './companion.ts';
import { H, paletteFor, SCENES, sceneFrames, W } from './sprites.ts';

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
          assert.ok((body.match(/f/g) ?? []).length > (scene === 'home' ? 12 : 30), 'fur');
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

describe('how each one talks', () => {
  it('says its own words when tapped, at least three different ones', () => {
    const all = new Set<string>();
    for (const a of ANIMALS) {
      assert.ok(new Set(a.says).size >= 3, a.name);
      for (const w of a.says) all.add(w);
    }
    assert.ok(all.size >= 20, 'every animal has its own words');
    assert.ok(ANIMALS.find((a) => a.id === 'dog')!.says.includes('Woof!'));
    assert.ok(ANIMALS.find((a) => a.id === 'cat')!.says.includes('Meow!'));
  });
  it('makes its own sound: a short call that is not the same as any other animal\'s', async () => {
    const { VOICES, callLength } = await import('./sounds.ts');
    const seen = new Set<string>();
    for (const a of ANIMALS) {
      const calls = VOICES[a.id];
      assert.ok(calls.length >= 1);
      for (const call of calls) {
        assert.ok(callLength(call) >= 200 && callLength(call) <= 1500, `${a.id} call is ${callLength(call)}ms`);
        for (const n of call) assert.ok(n.from > 50 && n.to > 50 && n.from < 6000 && n.to < 6000 && n.gain > 0 && n.gain <= 0.6 && n.dur > 0);
      }
      seen.add(JSON.stringify(calls));
    }
    assert.equal(seen.size, ANIMALS.length);
  });
  it('has a home of its own and a reaction, each well away from the other scenes', () => {
    for (const a of ANIMALS) {
      assert.ok(sceneFrames('react', a.id).frames.length >= 6, `${a.id} react`);
      assert.ok(sceneFrames('home', a.id).frames.length >= 6, `${a.id} home`);
      assert.notEqual(sceneFrames('home', a.id).frames[0].join(), sceneFrames('sit', a.id).frames[0].join(), `${a.id} home is not just sitting`);
    }
  });
});
