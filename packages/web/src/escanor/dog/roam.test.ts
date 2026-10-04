import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { cssFor, EXCURSIONS, nextDelay, orientation, pickExcursion, planExcursion, sample, type Geometry } from './roam.ts';

const g: Geometry = { vw: 1280, vh: 800, sw: 72, sh: 44, home: { x: 40, y: 770 }, top: 8 };
const seeded = (seed = 7) => () => ((seed = (seed * 16807) % 2147483647) - 1) / 2147483646;

describe('orientation', () => {
  it('stands on the floor facing either way', () => {
    assert.deepEqual(orientation({ x: 0, y: 1 }, { x: 1, y: 0 }), { rotate: 0, mirror: false });
    assert.deepEqual(orientation({ x: 0, y: 1 }, { x: -1, y: 0 }), { rotate: 0, mirror: true });
  });
  it('finds a turn for every edge and direction it can walk', () => {
    for (const feet of [{ x: 0, y: 1 }, { x: -1, y: 0 }, { x: 0, y: -1 }, { x: 1, y: 0 }]) {
      for (const face of [{ x: 1, y: 0 }, { x: -1, y: 0 }, { x: 0, y: 1 }, { x: 0, y: -1 }]) {
        if (feet.x * face.x + feet.y * face.y !== 0) continue; // it cannot face along its own feet
        const o = orientation(feet, face);
        // applying the answer must really put the feet and the face where asked
        const a = (o.rotate * Math.PI) / 180;
        const rot = (p: { x: number; y: number }) => ({ x: Math.round(p.x * Math.cos(a) - p.y * Math.sin(a)) + 0, y: Math.round(p.x * Math.sin(a) + p.y * Math.cos(a)) + 0 });
        assert.deepEqual(rot({ x: 0, y: 1 }), feet);
        assert.deepEqual(rot({ x: o.mirror ? -1 : 1, y: 0 }), face);
      }
    }
    assert.equal(cssFor({ rotate: 180, mirror: true }), 'rotate(180deg) scaleX(-1)');
  });
});

describe('excursions', () => {
  it('there are five, all different', () => {
    assert.equal(new Set(EXCURSIONS).size, 5);
  });
  for (const kind of EXCURSIONS) {
    it(`${kind}: starts at home, ends at home, and every stop is on the screen (or just off its edge)`, () => {
      const plan = planExcursion(kind, g, seeded());
      assert.ok(plan.legs.length >= 3 && plan.total > 3000);
      const end = plan.legs[plan.legs.length - 1].to;
      assert.deepEqual(end, g.home);
      for (const l of plan.legs) {
        assert.ok(l.ms >= 1);
        assert.ok(l.to.x >= -g.sw && l.to.x <= g.vw + g.sw && l.to.y >= 0 && l.to.y <= g.vh, `${kind} leaves the screen at ${JSON.stringify(l.to)}`);
      }
    });
  }
  it('the patrol goes right round: it is upside down along the top and stands on both walls', () => {
    const plan = planExcursion('patrol', g, () => 0.1);
    const feet = plan.legs.map((l) => `${l.feet.x},${l.feet.y}`);
    assert.ok(feet.includes('0,-1'), 'ceiling');
    assert.ok(feet.includes('-1,0') && feet.includes('1,0'), 'both walls');
    const ceiling = plan.legs.find((l) => l.feet.y === -1)!;
    assert.ok(ceiling.to.y < 40, 'on the top edge');
  });
  it('the patrol can go either way round', () => {
    assert.notDeepEqual(planExcursion('patrol', g, () => 0.1).legs[0].to, planExcursion('patrol', g, () => 0.9).legs[0].to);
  });
  it('the peek goes out of sight, comes back half in, and returns from the left', () => {
    const plan = planExcursion('peek', g, seeded());
    assert.ok(plan.legs.some((l) => l.to.x > g.vw), 'goes off the right edge');
    assert.ok(plan.legs.some((l) => l.jump && l.to.x < 0), 'comes back from the left');
    const looking = plan.legs.find((l) => l.scene === 'sniff')!;
    assert.ok(looking.to.x < g.vw && looking.to.x > g.vw - g.sw, 'half in view');
  });
  it('the zoomies spin in the middle and the nap sleeps a long while', () => {
    assert.ok(planExcursion('zoomies', g, seeded()).legs.some((l) => l.scene === 'react'));
    const nap = planExcursion('nap', g, seeded()).legs.find((l) => l.scene === 'sleep')!;
    assert.ok(nap.ms >= 8000);
  });
  it('fits a phone-sized screen too', () => {
    const phone: Geometry = { vw: 390, vh: 844, sw: 72, sh: 44, home: { x: 40, y: 740 }, top: 44 };
    for (const kind of EXCURSIONS) {
      const plan = planExcursion(kind, phone, seeded());
      for (const l of plan.legs) assert.ok(l.to.x >= -phone.sw && l.to.x <= phone.vw + phone.sw, kind);
    }
  });
});

describe('sample', () => {
  const plan = planExcursion('stroll', g, seeded());
  it('starts at home, moves along the first leg, and ends at the last stop', () => {
    assert.deepEqual(sample(plan, g.home, 0).pos, g.home);
    const mid = sample(plan, g.home, plan.legs[0].ms / 2);
    assert.ok(mid.pos.x > g.home.x && mid.pos.x < plan.legs[0].to.x);
    const end = sample(plan, g.home, plan.total + 5);
    assert.equal(end.done, true);
    assert.deepEqual(end.pos, g.home);
  });
  it('stands still while it holds, with the scene of that leg', () => {
    const t = plan.legs[0].ms + 500;
    const s = sample(plan, g.home, t);
    assert.equal(s.leg.scene, 'sniff');
    assert.deepEqual(s.pos, plan.legs[0].to);
  });
  it('appears at the edge, not sliding across the screen, when a leg is a jump', () => {
    const peek = planExcursion('peek', g, seeded());
    const i = peek.legs.findIndex((l) => l.jump);
    const before = peek.legs.slice(0, i).reduce((n, l) => n + l.ms, 0);
    const s = sample(peek, g.home, before + 1);
    assert.ok(s.pos.x < 0);
  });
});

describe('when', () => {
  it('waits 20 to 60 seconds for the first outing and one to three minutes between the rest', () => {
    for (const r of [0, 0.5, 0.999]) {
      const first = nextDelay(() => r, true);
      assert.ok(first >= 20_000 && first <= 60_000);
      const later = nextDelay(() => r);
      assert.ok(later >= 60_000 && later <= 180_000);
    }
  });
  it('never picks the same outing twice running', () => {
    for (const last of EXCURSIONS) for (const r of [0, 0.3, 0.6, 0.99]) assert.notEqual(pickExcursion(() => r, last), last);
  });
});
