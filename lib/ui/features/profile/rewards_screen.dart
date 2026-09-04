import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/charging_models.dart';
import '../../core/app_state.dart';
import '../../core/widgets.dart';

enum _RewardCategory { rewards, history }

class RewardsScreen extends ConsumerStatefulWidget {
  const RewardsScreen({super.key});

  @override
  ConsumerState<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends ConsumerState<RewardsScreen> {
  RewardSummary? _summary;
  bool _loading = true;
  String? _error;
  String? _redeemingId;
  _RewardCategory _category = _RewardCategory.rewards;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await ref.read(stationRepositoryProvider).loadMyRewards();
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyErrorMessage(
          error,
          fallback: 'Could not load your rewards. Please try again.',
        );
      });
    }
  }

  void _message(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _redeem(Reward reward) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Redeem this reward?'),
            content: Text(
              '${reward.pointsRequired} points will be deducted. An RM ${reward.discountMyr.toStringAsFixed(2)} voucher will be added to My vouchers.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Redeem'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _redeemingId = reward.id);
    try {
      final summary = await ref
          .read(stationRepositoryProvider)
          .redeemReward(reward.id);
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _redeemingId = null;
        _category = _RewardCategory.history;
      });
      _message('Reward redeemed. Your voucher is ready to use.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _redeemingId = null);
      _message(
        friendlyErrorMessage(
          error,
          fallback: 'Could not redeem this reward. Please try again.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    final orderedRewards = [...?summary?.rewards]..sort(
      (left, right) => left.pointsRequired.compareTo(right.pointsRequired),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('My rewards'),
        actions: [
          IconButton(
            tooltip: 'Refresh rewards',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_outlined),
          ),
        ],
      ),
      body:
          _loading && summary == null
              ? const Center(child: CircularProgressIndicator())
              : _error != null && summary == null
              ? AppStateMessage(
                icon: Icons.stars_outlined,
                title: 'Could not load rewards',
                message: _error!,
                actionLabel: 'Retry',
                onAction: _refresh,
              )
              : RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _PointsCard(summary: summary!),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<_RewardCategory>(
                        segments: const [
                          ButtonSegment(
                            value: _RewardCategory.rewards,
                            icon: Icon(Icons.card_giftcard_outlined),
                            label: Text('Rewards'),
                          ),
                          ButtonSegment(
                            value: _RewardCategory.history,
                            icon: Icon(Icons.history),
                            label: Text('History'),
                          ),
                        ],
                        selected: {_category},
                        onSelectionChanged:
                            (selection) =>
                                setState(() => _category = selection.first),
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (_category == _RewardCategory.rewards) ...[
                      Text(
                        'Available rewards',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      if (orderedRewards.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(22),
                            child: Text(
                              'No rewards are available right now.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      else
                        for (final reward in orderedRewards) ...[
                          _RewardCard(
                            reward: reward,
                            pointsBalance: summary.pointsBalance,
                            redeeming: _redeemingId == reward.id,
                            onRedeem: () => _redeem(reward),
                          ),
                          const SizedBox(height: 10),
                        ],
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Redemption history',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          TextButton(
                            onPressed: () => context.push('/profile/vouchers'),
                            child: const Text('My vouchers'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (summary.history.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(22),
                            child: Text(
                              'You have not redeemed a reward yet.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      else
                        for (final redemption in summary.history) ...[
                          _RedemptionCard(redemption: redemption),
                          const SizedBox(height: 10),
                        ],
                    ],
                  ],
                ),
              ),
    );
  }
}

class _PointsCard extends StatelessWidget {
  const _PointsCard({required this.summary});

  final RewardSummary summary;

  @override
  Widget build(BuildContext context) {
    Reward? next;
    for (final reward in summary.rewards) {
      if (reward.pointsRequired > summary.pointsBalance &&
          (next == null || reward.pointsRequired < next.pointsRequired)) {
        next = reward;
      }
    }
    final progress =
        next == null
            ? 1.0
            : (summary.pointsBalance / next.pointsRequired)
                .clamp(0, 1)
                .toDouble();
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.stars_rounded),
                SizedBox(width: 10),
                Text('ChargeMY Points'),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${summary.pointsBalance}',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const Text('available points'),
            const SizedBox(height: 14),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 8),
            Text(
              next == null
                  ? 'You can redeem any currently available reward.'
                  : '${next.pointsRequired - summary.pointsBalance} more points to ${next.title}',
            ),
            const SizedBox(height: 6),
            const Text('Earn 1 point for each whole RM successfully paid.'),
          ],
        ),
      ),
    );
  }
}

class _RewardCard extends StatelessWidget {
  const _RewardCard({
    required this.reward,
    required this.pointsBalance,
    required this.redeeming,
    required this.onRedeem,
  });

  final Reward reward;
  final int pointsBalance;
  final bool redeeming;
  final VoidCallback onRedeem;

  @override
  Widget build(BuildContext context) {
    final canRedeem = pointsBalance >= reward.pointsRequired;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      Theme.of(context).colorScheme.secondaryContainer,
                  child: const Icon(Icons.card_giftcard_outlined),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reward.title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text('${reward.pointsRequired} points'),
                    ],
                  ),
                ),
                Text(
                  'RM ${reward.discountMyr.toStringAsFixed(2)} off',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            if (reward.description.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(reward.description),
            ],
            const SizedBox(height: 6),
            Text(
              'Minimum payment RM ${reward.effectiveMinimumSpendMyr.toStringAsFixed(2)}',
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: canRedeem && !redeeming ? onRedeem : null,
                icon:
                    redeeming
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.redeem_outlined),
                label: Text(
                  redeeming
                      ? 'Redeeming...'
                      : canRedeem
                      ? 'Redeem reward'
                      : '${reward.pointsRequired - pointsBalance} more points needed',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RedemptionCard extends StatelessWidget {
  const _RedemptionCard({required this.redemption});

  final RewardRedemption redemption;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const CircleAvatar(child: Icon(Icons.check_rounded)),
      title: Text(redemption.rewardTitle),
      subtitle: Text(
        'Added to My vouchers\n${MaterialLocalizations.of(context).formatMediumDate(redemption.redeemedAt)}',
      ),
      isThreeLine: true,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('-${redemption.pointsSpent} points'),
          Text('RM ${redemption.discountMyr.toStringAsFixed(2)} off'),
        ],
      ),
    ),
  );
}
