import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StripePaymentService {
  const StripePaymentService._();

  static const publishableKey = String.fromEnvironment(
    'STRIPE_PUBLISHABLE_KEY',
    defaultValue:
        'pk_test_51U3UscILMvYGIjvE1ebpwvotDbXgwqukfDinnKcDyzhhceM6u3GgoNVHp4EASMYHU3LyMhT7ApceCsy7ZWshZGWL00pGey5ysz',
  );

  static bool get isConfigured =>
      publishableKey.startsWith('pk_test_') ||
      publishableKey.startsWith('pk_live_');

  static Future<StripeCheckoutResult> payChargingSession({
    required double amountMyr,
    required String sessionId,
    required String stationId,
    String? voucherClaimId,
  }) async {
    if (!publishableKey.startsWith('pk_test_')) {
      throw StateError(
        'Stripe Test Mode is not configured. Run with '
        '--dart-define=STRIPE_PUBLISHABLE_KEY=pk_test_...',
      );
    }

    Stripe.publishableKey = publishableKey;
    Stripe.urlScheme = 'chargemy';
    await Stripe.instance.applySettings();

    final response = await Supabase.instance.client.functions.invoke(
      'create-payment-intent',
      body: {
        'amount': (amountMyr * 100).round().clamp(200, 100000000),
        'currency': 'myr',
        'sessionId': sessionId,
        'stationId': stationId,
        'voucherClaimId': voucherClaimId,
      },
    );
    final data = response.data;
    if (data is! Map || data['clientSecret'] is! String) {
      throw StateError('The payment service did not return a client secret.');
    }
    final finalAmount = (data['finalAmountMyr'] as num?)?.toDouble();
    final discount = (data['discountMyr'] as num?)?.toDouble();
    if (finalAmount == null || discount == null) {
      throw StateError('The payment service did not return the payment total.');
    }

    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        paymentIntentClientSecret: data['clientSecret'] as String,
        merchantDisplayName: 'ChargeMY Test Checkout',
        primaryButtonLabel: 'Pay charging fee',
        style: ThemeMode.light,
        googlePay: const PaymentSheetGooglePay(
          merchantCountryCode: 'MY',
          testEnv: true,
        ),
      ),
    );
    await Stripe.instance.presentPaymentSheet();
    return StripeCheckoutResult(
      originalAmountMyr: amountMyr,
      finalAmountMyr: finalAmount,
      discountMyr: discount,
      voucherClaimId: voucherClaimId,
    );
  }
}

class StripeCheckoutResult {
  const StripeCheckoutResult({
    required this.originalAmountMyr,
    required this.finalAmountMyr,
    required this.discountMyr,
    this.voucherClaimId,
  });

  final double originalAmountMyr;
  final double finalAmountMyr;
  final double discountMyr;
  final String? voucherClaimId;
}
