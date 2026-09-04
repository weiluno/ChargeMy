import 'package:chargemy/domain/models/charging_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fixed voucher keeps at least RM2 for Stripe', () {
    final voucher = Voucher(
      claimId: 'claim',
      code: 'SAVE5',
      title: 'Save RM5',
      discountType: 'fixed',
      discountValue: 5,
      minimumSpendMyr: 0,
      claimedAt: DateTime(2026),
    );

    expect(voucher.effectiveMinimumSpendMyr, 7);
    expect(voucher.canApplyToStripePayment(6.99), isFalse);
    expect(voucher.canApplyToStripePayment(7), isTrue);
  });

  test('reward minimum is discount plus RM2 when admin minimum is lower', () {
    const reward = Reward(
      id: 'reward',
      title: 'RM10 reward',
      description: '',
      pointsRequired: 100,
      discountMyr: 10,
      minimumSpendMyr: 3,
      isActive: true,
    );

    expect(reward.effectiveMinimumSpendMyr, 12);
  });
}
