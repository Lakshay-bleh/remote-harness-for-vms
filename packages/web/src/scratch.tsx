import React, { useEffect, useRef } from 'react';
import { createRoot } from 'react-dom/client';
import './styles.css';
import { ANIMALS, type Animal } from './escanor/dog/animals';
import { paint } from './escanor/dog/PixelDog';
import { H, paletteFor, sceneFrames, SCENES, W, type Scene } from './escanor/dog/sprites';
const q = new URLSearchParams(location.search);
const a = (q.get('a') || 'dog') as Animal;
const only = q.get('s') as Scene | null;
function Frame({ animal, scene, i, scale }: { animal: Animal; scene: Scene; i: number; scale: number }) {
  const ref = useRef<HTMLCanvasElement>(null);
  useEffect(() => { const c = ref.current!; paint(c.getContext('2d')!, sceneFrames(scene, animal).frames[i], scale, paletteFor(animal)); }, []);
  return <canvas ref={ref} width={W * scale} height={H * scale} style={{ imageRendering: 'pixelated', width: W * scale, height: H * scale }} />;
}
createRoot(document.getElementById('root')!).render(
  <div className="bg-canvas p-2 text-ink" style={{ width: 1000 }}>
    <div className="text-sm">{ANIMALS.find((x) => x.id === a)?.name} frames</div>
    {SCENES.filter((s) => !only || s === only).map((s) => (
      <div key={s} className="mb-2"><div className="text-[10px] text-muted">{s}</div>
        <div className="flex flex-wrap gap-1">{sceneFrames(s === s ? s : s, a).frames.map((_, i) => <Frame key={i} animal={a} scene={s} i={i} scale={q.get("z") ? Number(q.get("z")) : 3} />)}</div>
      </div>
    ))}
  </div>,
);
