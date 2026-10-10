import type { AssistantCapabilities } from '@remote-harness/shared/escanor';

type Integration = AssistantCapabilities['integrations'][number];

/**
 * Which connected services to show under the composer, and whether to invite connecting one. A service whose reach
 * could not be checked (null) counts: it is connected, and the machine reads connections live once it is up.
 */
export function assistantReach(integrations: Integration[] | undefined): { usable: Integration[]; invite: boolean } {
  const all = integrations ?? [];
  return {
    usable: all.filter((i) => i.available_to_assistant !== false && !i.needs_reconnect),
    invite: integrations !== undefined && all.length === 0,
  };
}
