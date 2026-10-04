/**
 * Where the voice button sits. It is stored as a fraction of the free space (0 = left or top edge, 1 = right or bottom edge), so it
 * lands in the same place on a rotated phone, with the keyboard gone, or on another screen size, and never off-screen.
 */

export interface OrbPos {
  x: number;
  y: number;
}

export const ORB_SIZE = 56;
/** Breathing room between the button and the screen's edge. */
export const ORB_MARGIN = 6;
const KEY = 'escanor.orb.v1';

/** Out of the way of the message box and its send button: right edge, a little above the middle. */
export const DEFAULT_ORB: OrbPos = { x: 1, y: 0.4 };

const clamp01 = (n: number) => Math.min(1, Math.max(0, n));

export interface View {
  width: number;
  height: number;
  /** Space the system keeps for itself at the top (status bar) and bottom (gesture bar). */
  insetTop: number;
  insetBottom: number;
}

/** The fraction for the button's centre being at a point on the screen. */
export function posFromPoint(clientX: number, clientY: number, v: View, size = ORB_SIZE): OrbPos {
  const spanX = Math.max(1, v.width - size - ORB_MARGIN * 2);
  const spanY = Math.max(1, v.height - v.insetTop - v.insetBottom - size - ORB_MARGIN * 2);
  return { x: clamp01((clientX - size / 2 - ORB_MARGIN) / spanX), y: clamp01((clientY - size / 2 - v.insetTop - ORB_MARGIN) / spanY) };
}

/** CSS for a position: pure `calc`, so it follows the screen's size and safe areas by itself. */
export function orbCss(p: OrbPos, size = ORB_SIZE): { left: string; top: string } {
  const x = clamp01(p.x);
  const y = clamp01(p.y);
  return {
    left: `calc(${ORB_MARGIN}px + ${x} * (100vw - ${size + ORB_MARGIN * 2}px))`,
    top: `calc(env(safe-area-inset-top, 0px) + ${ORB_MARGIN}px + ${y} * (100svh - env(safe-area-inset-top, 0px) - env(safe-area-inset-bottom, 0px) - ${size + ORB_MARGIN * 2}px))`,
  };
}

export function parseOrb(raw: string | null): OrbPos | null {
  if (!raw) return null;
  try {
    const v = JSON.parse(raw) as Partial<OrbPos>;
    return typeof v.x === 'number' && typeof v.y === 'number' && Number.isFinite(v.x) && Number.isFinite(v.y) ? { x: clamp01(v.x), y: clamp01(v.y) } : null;
  } catch {
    return null;
  }
}

export function loadOrb(): OrbPos {
  try {
    return parseOrb(localStorage.getItem(KEY)) ?? DEFAULT_ORB;
  } catch {
    return DEFAULT_ORB;
  }
}

export function saveOrb(p: OrbPos): void {
  try {
    localStorage.setItem(KEY, JSON.stringify({ x: clamp01(p.x), y: clamp01(p.y) }));
  } catch {
    // not remembered; it still stays where it was dropped for this visit
  }
}

/** Moving less than this is a tap, not a drag. */
export const DRAG_SLOP_PX = 8;
export const movedFar = (dx: number, dy: number): boolean => Math.hypot(dx, dy) > DRAG_SLOP_PX;
