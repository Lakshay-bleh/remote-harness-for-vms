import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { openCheckout } from './razorpay';

type Options = { handler: (r: unknown) => void; modal: { ondismiss: () => void } };

/** A stand-in for Razorpay's form: the test plays the person (fail, retry, pay, close). */
function fakeForm() {
  const form: { options?: Options; failed?: (r: { error?: { description?: string } }) => void; opened: boolean } = { opened: false };
  class Razorpay {
    constructor(options: Record<string, unknown>) {
      form.options = options as unknown as Options;
    }
    on(_event: 'payment.failed', cb: (r: { error?: { description?: string } }) => void) {
      form.failed = cb;
    }
    open() {
      form.opened = true;
    }
  }
  return { Razorpay, form };
}

const order = { key: 'rzp_test', subscriptionId: 'sub_1', planName: 'Pro' };
const paidResponse = { razorpay_payment_id: 'pay_1', razorpay_subscription_id: 'sub_1', razorpay_signature: 'sig' };

describe('openCheckout', () => {
  it('a failed attempt keeps waiting, and a retry that succeeds is reported as paid', async () => {
    const { Razorpay, form } = fakeForm();
    const result = openCheckout(Razorpay, order);
    assert.ok(form.opened);
    form.failed!({ error: { description: 'Card declined' } });
    form.options!.handler(paidResponse);
    assert.deepEqual(await result, { kind: 'paid', response: paidResponse });
  });

  it('closing the form after a failure reports the failure', async () => {
    const { Razorpay, form } = fakeForm();
    const result = openCheckout(Razorpay, order);
    form.failed!({ error: { description: 'Card declined' } });
    form.options!.modal.ondismiss();
    assert.deepEqual(await result, { kind: 'failed', message: 'Card declined' });
  });

  it('closing it without trying is "closed", and a failure without words gets a plain one', async () => {
    const a = fakeForm();
    const closed = openCheckout(a.Razorpay, order);
    a.form.options!.modal.ondismiss();
    assert.deepEqual(await closed, { kind: 'closed' });

    const b = fakeForm();
    const failed = openCheckout(b.Razorpay, order);
    b.form.failed!({});
    b.form.options!.modal.ondismiss();
    assert.match(((await failed) as { message: string }).message, /did not go through/);
  });
});
