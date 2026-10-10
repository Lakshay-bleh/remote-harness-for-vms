import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import type { AssistantModel, AssistantModels } from './client';
import { AUTO_ID, chosenId, chosenLabel, hiddenCount, modelToSend, pickerGroups } from './modelPicker';

const m = (id: string, provider: string, over: Partial<AssistantModel> = {}): AssistantModel => ({ id, provider, label: id.split(':')[1], default: false, ...over });

describe('the chat’s model picker', () => {
  const models = [
    m('ollama:llama3', 'ollama', { local: true, provider_label: 'Local models (on our server)' }),
    m('anthropic:sonnet', 'anthropic', { provider_label: 'Claude' }),
    m('anthropic:opus', 'anthropic', { provider_label: 'Claude', verified: true }),
    m('openai:gpt', 'openai', { available: false, reason: 'no_key' }),
  ];

  it('lists only models that can answer, proven ones first, models on our own machine last', () => {
    const g = pickerGroups(models);
    assert.deepEqual(g.map((x) => x.label), ['Claude', 'Local models']);
    assert.deepEqual(g[0].models.map((x) => x.id), ['anthropic:opus', 'anthropic:sonnet']);
    assert.equal(hiddenCount(models), 1);
  });

  it('is Auto unless the person chose a model that can still answer', () => {
    assert.equal(chosenId(models, null), AUTO_ID);
    assert.equal(chosenId(models, 'anthropic:sonnet'), 'anthropic:sonnet');
    assert.equal(chosenId(models, 'openai:gpt'), AUTO_ID);
    assert.equal(chosenId(models, 'gone:model'), AUTO_ID);
  });

  it('labels Auto with what it would use right now', () => {
    assert.equal(chosenLabel(models, AUTO_ID, { resolves_to: 'anthropic:opus' }), 'Auto · opus');
    assert.equal(chosenLabel(models, AUTO_ID), 'Auto');
    assert.equal(chosenLabel(models, 'anthropic:sonnet'), 'sonnet');
  });

  it('sends the chosen model, Auto only to a server that has it, and nothing before the list has loaded', () => {
    const withAuto: AssistantModels = { models, default: null, auto: { id: 'auto', label: 'Auto', available: true, resolves_to: 'anthropic:opus', detail: '' } };
    const old: AssistantModels = { models, default: null };
    assert.equal(modelToSend(withAuto, 'anthropic:sonnet'), 'anthropic:sonnet');
    assert.equal(modelToSend(withAuto, null), 'auto');
    assert.equal(modelToSend(old, null), undefined);
    assert.equal(modelToSend(old, 'openai:gpt'), undefined);
    assert.equal(modelToSend(null, 'anthropic:sonnet'), undefined);
  });
});
