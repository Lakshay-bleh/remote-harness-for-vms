import { escanor } from '../client';
import { applyRoute, getComputerPrefs } from '../computer/computerPrefs';
import { ComputerClient, type PairedComputer } from '../computer/lib/client';

const id = () => Math.random().toString(36).slice(2, 10);

/**
 * Say one sentence to a paired computer and wait for what it says back. Connects the way the person chose for that computer
 * (Wi-Fi, cloud or automatic), asks, and hangs up. Throws the failure as it is, so it can be explained where to fix it.
 */
export async function chatWithComputer(c: PairedComputer, text: string): Promise<string> {
  const { computer, cloud } = applyRoute(c, getComputerPrefs(c.id).route);
  const client = new ComputerClient(computer, { relay: cloud ? ({ agentId, deviceId, sealed }) => escanor.sendToComputer(agentId, deviceId, sealed) : null });
  try {
    await client.connect();
    const out = await client.request({ t: 'chat', id: id(), text }, { timeoutMs: 60_000 });
    const m = out.find((r) => r.t === 'reply' || r.t === 'error');
    if (!m) return '';
    if (m.t === 'error') throw new Error(m.message);
    return m.t === 'reply' ? m.reply : '';
  } finally {
    client.close();
  }
}
