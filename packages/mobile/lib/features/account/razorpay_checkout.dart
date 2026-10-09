import 'dart:async';

import 'package:razorpay_flutter/razorpay_flutter.dart';

/// Razorpay's own payment form, opened inside the app. Card, UPI and bank details are typed into Razorpay's form and never reach
/// Escanor.

sealed class PayResult {
  const PayResult();
}

class Paid extends PayResult {
  const Paid({required this.paymentId, required this.subscriptionId, required this.signature});
  final String paymentId;
  final String subscriptionId;
  final String signature;
}

class PayClosed extends PayResult {
  const PayClosed();
}

class PayFailed extends PayResult {
  const PayFailed(this.message);
  final String message;
}

/// What Razorpay's answer means. Pure, so it can be tested.
Paid payResultFromSuccess(Map<dynamic, dynamic> data, String subscriptionId) => Paid(
      paymentId: '${data['razorpay_payment_id'] ?? ''}',
      subscriptionId: '${data['razorpay_subscription_id'] ?? subscriptionId}',
      signature: '${data['razorpay_signature'] ?? ''}',
    );

PayResult payResultFromError(int? code, String? message) {
  if (code == Razorpay.PAYMENT_CANCELLED) return const PayClosed();
  if (code == Razorpay.NETWORK_ERROR) return const PayFailed('Could not load the payment form. Check your connection and try again. Nothing was charged.');
  final m = (message ?? '').trim();
  // Razorpay sometimes hands back its raw JSON error; only a plain sentence is worth showing.
  return PayFailed(m.isEmpty || m.startsWith('{') ? 'The payment did not go through. Nothing was charged.' : m);
}

Map<String, dynamic> checkoutOptions({required String key, required String subscriptionId, required String planName, String? name, String? email}) => {
      'key': key,
      'subscription_id': subscriptionId,
      'name': 'Escanor',
      'description': '$planName plan',
      'prefill': {'name': name ?? '', 'email': email ?? ''},
      'theme': {'color': '#f2a73b'},
    };

/// One open payment form. A failed attempt does not end it: Razorpay keeps the form open so the person can try another card or
/// UPI app, and a retry that succeeds must still reach [paid] (and so /billing/verify). Only paying, or the form closing, settles
/// it; closing it after a failure reports that failure rather than "cancelled". Pure, so it is tested.
class CheckoutSession {
  final _done = Completer<PayResult>();
  String? _lastFailure;

  Future<PayResult> get result => _done.future;
  bool get settled => _done.isCompleted;

  void paid(Paid p) => _settle(p);

  /// An attempt failed; the form stays open for another.
  void failed(String? message) {
    final m = (message ?? '').trim();
    _lastFailure = m.isEmpty ? 'The payment did not go through. Nothing was charged.' : m;
  }

  /// The form is gone: the last failure, if there was one, else cancelled.
  void closed() => _settle(_lastFailure != null ? PayFailed(_lastFailure!) : const PayClosed());

  /// Something that ends it outright (the form could not open).
  void fail(String message) => _settle(PayFailed(message));

  void _settle(PayResult r) {
    if (!_done.isCompleted) _done.complete(r);
  }

  /// What Razorpay's error event means here. On the phone the error event comes when the form has closed: cancelled by the
  /// person (after any failed attempts: the last failure), or a failure that ended it.
  void onError(int? code, String? message) {
    final r = payResultFromError(code, message);
    if (r is PayFailed) failed(r.message);
    closed();
  }
}

/// Open the payment form for a subscription the server created. Resolves when the person pays, or the form closes.
Future<PayResult> payWithRazorpay({required String key, required String subscriptionId, required String planName, String? name, String? email}) {
  final session = CheckoutSession();
  final rp = Razorpay();
  session.result.whenComplete(rp.clear);

  rp.on(Razorpay.EVENT_PAYMENT_SUCCESS, (dynamic data) => session.paid(payResultFromSuccess(data is Map ? data : const {}, subscriptionId)), rawMap: true);
  rp.on(Razorpay.EVENT_PAYMENT_ERROR, (dynamic r) {
    if (r is PaymentFailureResponse) {
      session.onError(r.code, r.message);
    } else {
      session.failed(null);
      session.closed();
    }
  });
  rp.on(Razorpay.EVENT_EXTERNAL_WALLET, (dynamic _) => session.fail('Paying with an outside wallet is not supported here. Nothing was charged.'));
  try {
    rp.open(checkoutOptions(key: key, subscriptionId: subscriptionId, planName: planName, name: name, email: email));
  } catch (_) {
    session.fail('The payment form is not available. Nothing was charged.');
  }
  return session.result;
}
