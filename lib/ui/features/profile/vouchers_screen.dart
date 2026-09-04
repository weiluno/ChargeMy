import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/charging_models.dart';
import '../../core/app_state.dart';
import '../../core/widgets.dart';

enum _VoucherCategory { vouchers, history }

class VouchersScreen extends ConsumerStatefulWidget {
  const VouchersScreen({super.key});

  @override
  ConsumerState<VouchersScreen> createState() => _VouchersScreenState();
}

class _VouchersScreenState extends ConsumerState<VouchersScreen> {
  final _codeController = TextEditingController();
  List<Voucher> _vouchers = [];
  bool _claiming = false;
  bool _loading = true;
  String? _loadError;
  _VoucherCategory _category = _VoucherCategory.vouchers;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final vouchers =
          await ref.read(stationRepositoryProvider).loadMyVouchers();
      if (!mounted) return;
      setState(() {
        _vouchers = vouchers;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = friendlyErrorMessage(
          error,
          fallback: 'Could not load your vouchers. Please try again.',
        );
      });
    }
  }

  void _message(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _claim() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a voucher code first.')),
      );
      return;
    }
    setState(() => _claiming = true);
    late Voucher claimed;
    try {
      claimed = await ref.read(stationRepositoryProvider).claimVoucher(code);
    } catch (error) {
      if (mounted) {
        setState(() => _claiming = false);
        _message(
          friendlyErrorMessage(
            error,
            fallback: 'Could not claim this voucher. Please try again.',
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    _codeController.clear();
    setState(() {
      _claiming = false;
      _category = _VoucherCategory.vouchers;
      _vouchers = [
        claimed,
        ..._vouchers.where((voucher) => voucher.claimId != claimed.claimId),
      ];
    });
    _message('${claimed.code} claimed successfully.');
  }

  List<Voucher> get _visibleVouchers =>
      _category == _VoucherCategory.vouchers
          ? _vouchers
              .where((voucher) => !voucher.isUsed && !voucher.isExpired)
              .toList()
          : _vouchers
              .where((voucher) => voucher.isUsed || voucher.isExpired)
              .toList();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('My vouchers'),
      actions: [
        IconButton(
          tooltip: 'Refresh vouchers',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_outlined),
        ),
      ],
    ),
    body:
        _loading && _vouchers.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null && _vouchers.isEmpty
            ? AppStateMessage(
              icon: Icons.confirmation_number_outlined,
              title: 'Could not load vouchers',
              message: _loadError!,
              actionLabel: 'Retry',
              onAction: _refresh,
            )
            : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.redeem_outlined),
                            const SizedBox(width: 10),
                            Text(
                              'Claim a voucher',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text('Enter a voucher code shared by ChargeMY.'),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _codeController,
                                textCapitalization:
                                    TextCapitalization.characters,
                                decoration: const InputDecoration(
                                  labelText: 'Voucher code',
                                  hintText: 'Example: SAVE10',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            FilledButton(
                              onPressed: _claiming ? null : _claim,
                              child: Text(_claiming ? 'Claiming' : 'Claim'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<_VoucherCategory>(
                    segments: const [
                      ButtonSegment(
                        value: _VoucherCategory.vouchers,
                        icon: Icon(Icons.local_offer_outlined),
                        label: Text('Voucher'),
                      ),
                      ButtonSegment(
                        value: _VoucherCategory.history,
                        icon: Icon(Icons.history),
                        label: Text('History'),
                      ),
                    ],
                    selected: {_category},
                    onSelectionChanged: (selection) {
                      setState(() => _category = selection.first);
                    },
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  _category == _VoucherCategory.vouchers
                      ? 'Vouchers (${_visibleVouchers.length})'
                      : 'Voucher history (${_visibleVouchers.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                if (_visibleVouchers.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        children: [
                          Icon(
                            _category == _VoucherCategory.vouchers
                                ? Icons.confirmation_number_outlined
                                : Icons.history,
                            size: 34,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _category == _VoucherCategory.vouchers
                                ? 'No vouchers'
                                : 'No voucher history',
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _category == _VoucherCategory.vouchers
                                ? 'Claim a code to add a voucher to your wallet.'
                                : 'Used and expired vouchers appear here.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  for (final voucher in _visibleVouchers) ...[
                    _VoucherCard(voucher: voucher),
                    const SizedBox(height: 10),
                  ],
              ],
            ),
  );
}

class _VoucherCard extends StatelessWidget {
  const _VoucherCard({required this.voucher});

  final Voucher voucher;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status =
        voucher.isUsed
            ? 'Used'
            : voucher.isExpired
            ? 'Expired'
            : voucher.isActive
            ? 'Available'
            : 'Unavailable';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              foregroundColor: scheme.primary,
              child: const Icon(Icons.local_offer_outlined),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          voucher.title,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      Chip(
                        label: Text(status),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (!voucher.isRewardVoucher)
                    Text(
                      voucher.code,
                      style: const TextStyle(letterSpacing: 1.1),
                    ),
                  const SizedBox(height: 6),
                  Text(voucher.discountLabel),
                  Text(
                    'Minimum spend RM ${voucher.effectiveMinimumSpendMyr.toStringAsFixed(2)}',
                  ),
                  if (voucher.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(voucher.description),
                  ],
                  if (voucher.expiresAt != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${voucher.isExpired ? 'Expired on' : 'Valid until'} ${MaterialLocalizations.of(context).formatMediumDate(voucher.expiresAt!)}',
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
