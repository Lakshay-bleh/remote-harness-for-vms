import { createRoot } from 'react-dom/client';
import { useEffect, useRef } from 'react';
import { paint } from './escanor/dog/PixelDog';
import { SCENES, sceneFrames, W, H } from './escanor/dog/sprites';
function F({ f }: { f: string[] }) { const r = useRef<HTMLCanvasElement>(null); useEffect(() => { paint(r.current!.getContext('2d')!, f, 4); }, [f]); return <canvas ref={r} width={W * 4} height={H * 4} style={{ background: '#141417', imageRendering: 'pixelated' }} />; }
createRoot(document.getElementById('root')!).render(<div>{SCENES.map((s) => <div key={s}><div>{s}</div><div className="g" style={{ gap: 4 }}>{sceneFrames(s).frames.map((f, i) => <F key={i} f={f} />)}</div></div>)}</div>);
