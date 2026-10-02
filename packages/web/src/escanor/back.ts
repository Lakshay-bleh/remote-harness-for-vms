import { App as CapApp } from '@capacitor/app';
import { useEffect, useRef } from 'react';
import { isNative } from '../api';

/** What the phone's back button should undo next: the sheet that is open, else the settings page, else leave. */
export class BackStack {
  private stack: Array<{ fn: () => void; priority: number }> = [];
  /** Higher priority is asked first; among equals, the most recent. The shell uses 0 so anything inside a screen goes first. */
  push(fn: () => void, priority = 1): void {
    this.stack.push({ fn, priority });
  }
  remove(fn: () => void): void {
    const i = this.stack.map((e) => e.fn).lastIndexOf(fn);
    if (i >= 0) this.stack.splice(i, 1);
  }
  /** Runs the top handler. False when there is nothing to undo. */
  press(): boolean {
    let top: { fn: () => void; priority: number } | undefined;
    for (const e of this.stack) if (!top || e.priority >= top.priority) top = e;
    if (!top) return false;
    top.fn();
    return true;
  }
}

const back = new BackStack();
let installed = false;
function install(): void {
  if (installed || !isNative()) return;
  installed = true;
  // Without this the Android back button closes the whole app from anywhere.
  void CapApp.addListener('backButton', () => {
    if (!back.press()) void CapApp.minimizeApp();
  });
}

/** While `active`, the phone's back button runs `onBack`. Higher `priority` goes first; the shell's own fallback uses 0. */
export function useHardwareBack(active: boolean, onBack: () => void, priority = 1): void {
  const latest = useRef(onBack);
  latest.current = onBack;
  useEffect(() => {
    if (!active) return;
    install();
    const fn = () => latest.current();
    back.push(fn, priority);
    return () => back.remove(fn);
  }, [active, priority]);
}
