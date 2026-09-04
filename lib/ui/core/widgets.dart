import 'package:flutter/material.dart';

import '../../domain/models/charging_models.dart';

String friendlyErrorMessage(
  Object? error, {
  String fallback = 'Something went wrong. Please try again.',
}) {
  final raw = '${error ?? ''}'.toLowerCase();
  if (raw.contains('over_email_send_rate_limit') ||
      raw.contains('rate limit') ||
      raw.contains('too many requests') ||
      raw.contains('can only request this after')) {
    return 'Please wait a moment before requesting another verification code.';
  }
  if (raw.contains('invalid login credentials') ||
      raw.contains('invalid-credential')) {
    return 'That email or password is not correct.';
  }
  if (raw.contains('email already registered') ||
      raw.contains('already exists for this email') ||
      raw.contains('email-already-in-use')) {
    return 'An account already exists for this email. Try signing in.';
  }
  if (raw.contains('invalid otp') ||
      raw.contains('otp expired') ||
      raw.contains('invalid verification code') ||
      raw.contains('token has expired')) {
    return 'That verification code is invalid or has expired. Request a new code and try again.';
  }
  if (raw.contains('jwt expired') ||
      raw.contains('refresh token') ||
      raw.contains('session not found')) {
    return 'Your sign-in session has expired. Please sign in again.';
  }
  if (raw.contains('invalid email') || raw.contains('invalid-email')) {
    return 'Enter a valid email address.';
  }
  if (raw.contains('weak-password')) {
    return 'Use a password with at least 6 characters.';
  }
  if (raw.contains('cannot remove your own') ||
      raw.contains('own administrator')) {
    return 'You cannot change your own administrator role.';
  }
  if (raw.contains('sign in is required')) {
    return 'Please sign in before using vouchers.';
  }
  if (raw.contains('do not have enough points')) {
    return 'You do not have enough points for this reward.';
  }
  if (raw.contains('reward is no longer available')) {
    return 'This reward is currently unavailable.';
  }
  if (raw.contains('reward_catalog') ||
      raw.contains('my_reward_points') ||
      raw.contains('my_reward_redemptions') ||
      raw.contains('redeem_reward')) {
    return 'Rewards setup needs updating. Please run the latest database schema.';
  }
  if (raw.contains('already claimed') ||
      ((raw.contains('duplicate key') || raw.contains('unique constraint')) &&
          raw.contains('voucher_claim'))) {
    return 'You have already claimed this voucher. Check Available vouchers or History.';
  }
  if (raw.contains('voucher has expired')) {
    return 'This voucher has expired and can no longer be used.';
  }
  if (raw.contains('voucher is currently paused')) {
    return 'This voucher is currently paused and cannot be used.';
  }
  if (raw.contains('voucher is not available yet')) {
    return 'This voucher is not available yet.';
  }
  if ((raw.contains('duplicate key') || raw.contains('unique constraint')) &&
      (raw.contains('voucher') || raw.contains('code'))) {
    return 'This voucher code already exists. Please use a different code.';
  }
  if (raw.contains('voucher has reached') || raw.contains('claim limit')) {
    return 'This voucher has reached its claim limit.';
  }
  if (raw.contains('voucher code is not available') ||
      raw.contains('voucher is no longer available')) {
    return 'This voucher code is invalid, expired, or unavailable.';
  }
  if (raw.contains('voucher requires a minimum spend')) {
    return 'This voucher does not meet the minimum spend for this payment.';
  }
  if (raw.contains('final payment must be at least') ||
      raw.contains('amount must be between 200')) {
    return 'This voucher would reduce the payment below Stripe’s RM 2.00 minimum.';
  }
  if (raw.contains('voucher could not be applied') ||
      raw.contains('payment amount does not match the selected voucher')) {
    return 'This voucher could not be applied. It may be paused, expired, or already used.';
  }
  if (raw.contains('payment service is not configured') ||
      raw.contains('did not return a client secret') ||
      raw.contains('did not return the payment total')) {
    return 'The payment service is not ready. Please try again later.';
  }
  if (raw.contains('payment canceled') ||
      raw.contains('payment cancelled') ||
      raw.contains('canceled')) {
    return 'Payment was cancelled. No charge was made.';
  }
  if (raw.contains('card declined') || raw.contains('card_declined')) {
    return 'Your card was declined. Try another payment method.';
  }
  if (raw.contains('discount_value') ||
      raw.contains('minimum_spend') ||
      raw.contains('max_redemptions') ||
      raw.contains('voucher details are invalid')) {
    return 'Check the voucher discount, minimum spend, and claim limit.';
  }
  if (raw.contains('my_vouchers') ||
      raw.contains('claim_voucher') ||
      raw.contains('preview_voucher_payment') ||
      raw.contains('record_charging_payment')) {
    return 'Voucher setup needs updating. Please run the latest database schema.';
  }
  if (raw.contains('permission') ||
      raw.contains('not allowed') ||
      raw.contains('row-level security') ||
      raw.contains('rls')) {
    return 'You do not have permission to perform this action.';
  }
  if (raw.contains('network') ||
      raw.contains('socket') ||
      raw.contains('connection') ||
      raw.contains('timed out')) {
    return 'Could not connect to the service. Check your internet connection and try again.';
  }
  if (raw.contains('postgrest') ||
      raw.contains('supabase') ||
      raw.contains('statuscode') ||
      raw.contains('status code') ||
      raw.contains('code:') ||
      raw.contains('details:')) {
    return fallback;
  }
  return fallback;
}

Color statusColor(PileStatus status) {
  return switch (status) {
    PileStatus.available => const Color(0xFF15A56C),
    PileStatus.reserved => const Color(0xFFDD9814),
    PileStatus.occupied => const Color(0xFFDD9814),
    PileStatus.offline => const Color(0xFFD53D3D),
    PileStatus.maintenance => const Color(0xFFD53D3D),
  };
}

String statusLabel(PileStatus status) {
  return switch (status) {
    PileStatus.available => 'Available',
    PileStatus.reserved => 'Occupied',
    PileStatus.occupied => 'Occupied',
    PileStatus.offline => 'Offline',
    PileStatus.maintenance => 'Maintenance',
  };
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});

  final PileStatus status;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: SizedBox(
          width: 76,
          child: Text(
            statusLabel(status),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (action != null) action!,
      ],
    );
  }
}

class AppStateMessage extends StatelessWidget {
  const AppStateMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor:
                      Theme.of(context).colorScheme.secondaryContainer,
                  child: Icon(
                    icon,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(message, textAlign: TextAlign.center),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: onAction,
                    child: Text(actionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
