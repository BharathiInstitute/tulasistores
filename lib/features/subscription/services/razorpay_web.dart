/// Razorpay Checkout.js interop for Flutter web.
///
/// Uses dart:js_interop to call Razorpay's JavaScript SDK directly,
/// since razorpay_flutter only supports Android/iOS.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

@JS('Razorpay')
extension type _RazorpayJS._(JSObject _) implements JSObject {
  external _RazorpayJS(JSObject options);
  external void open();
}

/// Returns true if the browser is on a mobile device.
bool _isMobileBrowser() {
  final ua = web.window.navigator.userAgent.toLowerCase();
  return ua.contains('android') ||
      ua.contains('iphone') ||
      ua.contains('ipad') ||
      ua.contains('mobile');
}

/// Checks the current URL for Razorpay redirect callback parameters.
///
/// After a mobile UPI payment, Razorpay redirects back with
/// ?razorpay_payment_id=...&razorpay_subscription_id=...&razorpay_signature=...
/// Returns the parameters if present, null otherwise.
Map<String, String>? checkPaymentRedirectParams() {
  final uri = Uri.parse(web.window.location.href);
  final paymentId = uri.queryParameters['razorpay_payment_id'];
  final subId = uri.queryParameters['razorpay_subscription_id'];
  final signature = uri.queryParameters['razorpay_signature'];

  if (paymentId != null && paymentId.isNotEmpty) {
    // Clean the URL (remove payment params) without reload
    final cleanUri = uri.replace(queryParameters: {});
    web.window.history.replaceState(JSObject(), '', cleanUri.toString());

    return {
      'razorpay_payment_id': paymentId,
      'razorpay_subscription_id': subId ?? '',
      'razorpay_signature': signature ?? '',
    };
  }
  return null;
}

/// Opens Razorpay Checkout on web using Checkout.js.
///
/// On mobile browsers, uses redirect mode with callback_url for reliable
/// UPI intent handling. On desktop, uses JS handler callbacks.
///
/// [options] must include 'key', 'subscription_id', 'name', etc.
/// [onSuccess] called with paymentId, subscriptionId, signature.
/// [onError] called with error code and description.
/// [onDismiss] called when user closes the modal without paying.
void openRazorpayWeb({
  required Map<String, dynamic> options,
  required void Function(
    String paymentId,
    String subscriptionId,
    String signature,
  )
  onSuccess,
  required void Function(int code, String description) onError,
  required void Function() onDismiss,
}) {
  final jsOptions = _jsifyMap(options);

  if (_isMobileBrowser()) {
    // Mobile: use redirect mode — UPI apps kill the browser tab's JS context
    final currentUrl = web.window.location.href.split('?').first;
    jsOptions['callback_url'] = currentUrl.toJS;
  }

  // Set handler callback (Razorpay success — works on desktop, fallback on mobile)
  jsOptions['handler'] = ((JSObject response) {
    final paymentId = (response['razorpay_payment_id'] as JSString).toDart;
    final subId = (response['razorpay_subscription_id'] as JSString).toDart;
    final signature = (response['razorpay_signature'] as JSString).toDart;
    onSuccess(paymentId, subId, signature);
  }).toJS;

  // Set modal.ondismiss callback
  final modal = jsOptions['modal'] as JSObject? ?? JSObject();
  modal['ondismiss'] = (() {
    onDismiss();
  }).toJS;
  jsOptions['modal'] = modal;

  final rzp = _RazorpayJS(jsOptions);
  rzp.open();
}

/// Recursively convert a Dart Map to a JSObject.
JSObject _jsifyMap(Map<String, dynamic> map) {
  final obj = JSObject();
  for (final entry in map.entries) {
    final value = entry.value;
    if (value is Map<String, dynamic>) {
      obj[entry.key] = _jsifyMap(value);
    } else if (value is String) {
      obj[entry.key] = value.toJS;
    } else if (value is int) {
      obj[entry.key] = value.toJS;
    } else if (value is double) {
      obj[entry.key] = value.toJS;
    } else if (value is bool) {
      obj[entry.key] = value.toJS;
      // ignore: invalid_runtime_check_with_js_interop_types
    } else if (value is JSAny?) {
      obj[entry.key] = value!;
    }
  }
  return obj;
}
