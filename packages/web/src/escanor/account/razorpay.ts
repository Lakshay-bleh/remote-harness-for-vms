/** Razorpay's own payment form, opened inside the app. Card, UPI and bank details are typed into Razorpay's form and never reach Escanor. */

interface RazorpayResponse {
  razorpay_payment_id: string;
  razorpay_subscription_id: string;
  razorpay_signature: string;
}
interface RazorpayInstance {
  open(): void;
  on(event: 'payment.failed', cb: (r: { error?: { description?: string } }) => void): void;
}
declare global {
  interface Window {
    Razorpay?: new (options: Record<string, unknown>) => RazorpayInstance;
  }
}

const SCRIPT = 'https://checkout.razorpay.com/v1/checkout.js';
let loading: Promise<void> | null = null;

export function loadRazorpay(): Promise<void> {
  if (window.Razorpay) return Promise.resolve();
  loading ??= new Promise<void>((resolve, reject) => {
    const tag = document.createElement('script');
    tag.src = SCRIPT;
    tag.async = true;
    tag.onload = () => resolve();
    tag.onerror = () => {
      loading = null;
      tag.remove();
      reject(new Error('Could not load the payment form. Check your connection and try again. Nothing was charged.'));
    };
    document.head.appendChild(tag);
  });
  return loading;
}

export type PayResult = { kind: 'paid'; response: RazorpayResponse } | { kind: 'closed' } | { kind: 'failed'; message: string };

type RazorpayCtor = new (options: Record<string, unknown>) => RazorpayInstance;

/** Open the payment form for a subscription the server created. Resolves when the person pays, or closes the form. */
export async function payWithRazorpay(o: { key: string; subscriptionId: string; planName: string; name?: string | null; email?: string | null }): Promise<PayResult> {
  await loadRazorpay();
  const Razorpay = window.Razorpay;
  if (!Razorpay) throw new Error('The payment form is not available. Nothing was charged.');
  return openCheckout(Razorpay, o);
}

/**
 * The form itself. A failed attempt does not end it: Razorpay keeps the form open so the person can try another card or UPI app,
 * and a retry that succeeds must still reach the handler (and so /billing/verify). Only paying, or closing the form, settles it;
 * closing it after a failure reports that failure rather than "cancelled".
 */
export function openCheckout(Razorpay: RazorpayCtor, o: { key: string; subscriptionId: string; planName: string; name?: string | null; email?: string | null }): Promise<PayResult> {
  return new Promise<PayResult>((resolve) => {
    let lastFailure: string | null = null;
    const form = new Razorpay({
      key: o.key,
      subscription_id: o.subscriptionId,
      name: 'Escanor',
      description: `${o.planName} plan`,
      prefill: { name: o.name ?? '', email: o.email ?? '' },
      theme: { color: '#f2a73b' },
      handler: (response: RazorpayResponse) => resolve({ kind: 'paid', response }),
      modal: { ondismiss: () => resolve(lastFailure ? { kind: 'failed', message: lastFailure } : { kind: 'closed' }) },
    });
    form.on('payment.failed', (r) => void (lastFailure = r.error?.description || 'The payment did not go through. Nothing was charged.'));
    form.open();
  });
}
