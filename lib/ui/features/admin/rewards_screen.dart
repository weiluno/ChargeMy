import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/widgets.dart';

class RewardsAdminScreen extends ConsumerStatefulWidget {
  const RewardsAdminScreen({super.key});

  @override
  ConsumerState<RewardsAdminScreen> createState() => _RewardsAdminScreenState();
}

class _RewardsAdminScreenState extends ConsumerState<RewardsAdminScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

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
      final rows = await ref.read(stationRepositoryProvider).loadAdminRewards();
      if (!mounted) return;
      setState(() {
        _rows = rows.map(Map<String, dynamic>.from).toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyErrorMessage(
          error,
          fallback: 'Could not load rewards. Please try again.',
        );
      });
    }
  }

  void _message(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _create() async {
    final draft = await showDialog<_RewardDraft>(
      context: context,
      builder: (_) => const _RewardEditorDialog(),
    );
    if (draft == null || !mounted) return;
    try {
      final row = await ref
          .read(stationRepositoryProvider)
          .createReward(
            title: draft.title,
            description: draft.description,
            pointsRequired: draft.pointsRequired,
            discountMyr: draft.discountMyr,
            minimumSpendMyr: draft.minimumSpendMyr,
          );
      if (!mounted) return;
      setState(() {
        _rows = [..._rows, row]..sort(
          (left, right) => ((left['points_required'] as num?)?.toInt() ?? 0)
              .compareTo((right['points_required'] as num?)?.toInt() ?? 0),
        );
      });
      _message('Reward created successfully.');
    } catch (error) {
      if (mounted) {
        _message(
          friendlyErrorMessage(
            error,
            fallback: 'Could not create the reward. Please try again.',
          ),
        );
      }
    }
  }

  Future<void> _edit(Map<String, dynamic> reward) async {
    final draft = await showDialog<_RewardDraft>(
      context: context,
      builder:
          (_) => _RewardEditorDialog(
            initial: _RewardDraft(
              title: '${reward['title']}',
              description: '${reward['description'] ?? ''}',
              pointsRequired: (reward['points_required'] as num?)?.toInt() ?? 0,
              discountMyr: (reward['discount_myr'] as num?)?.toDouble() ?? 0,
              minimumSpendMyr:
                  (reward['minimum_spend_myr'] as num?)?.toDouble() ?? 0,
            ),
          ),
    );
    if (draft == null || !mounted) return;
    try {
      final updated = await ref
          .read(stationRepositoryProvider)
          .updateReward(
            rewardId: '${reward['id']}',
            title: draft.title,
            description: draft.description,
            pointsRequired: draft.pointsRequired,
            discountMyr: draft.discountMyr,
            minimumSpendMyr: draft.minimumSpendMyr,
          );
      if (!mounted) return;
      setState(() {
        _rows =
            _rows
                .map(
                  (row) =>
                      '${row['id']}' == '${reward['id']}'
                          ? {...row, ...updated}
                          : row,
                )
                .toList()
              ..sort(
                (left, right) =>
                    ((left['points_required'] as num?)?.toInt() ?? 0).compareTo(
                      (right['points_required'] as num?)?.toInt() ?? 0,
                    ),
              );
      });
      _message('Reward updated successfully.');
    } catch (error) {
      if (mounted) {
        _message(
          friendlyErrorMessage(
            error,
            fallback: 'Could not update the reward. Please try again.',
          ),
        );
      }
    }
  }

  Future<void> _setActive(Map<String, dynamic> reward, bool isActive) async {
    try {
      await ref
          .read(stationRepositoryProvider)
          .setRewardActive(rewardId: '${reward['id']}', isActive: isActive);
      if (!mounted) return;
      setState(() {
        _rows =
            _rows
                .map(
                  (row) =>
                      '${row['id']}' == '${reward['id']}'
                          ? {...row, 'is_active': isActive}
                          : row,
                )
                .toList();
      });
      _message(
        isActive
            ? 'Reward activated successfully.'
            : 'Reward paused successfully.',
      );
    } catch (error) {
      if (mounted) {
        _message(
          friendlyErrorMessage(
            error,
            fallback: 'Could not change the reward status. Please try again.',
          ),
        );
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> reward) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Delete reward?'),
            content: Text(
              'Hide ${reward['title']} from the reward catalogue? Existing vouchers already redeemed by users will remain available.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(stationRepositoryProvider).deleteReward('${reward['id']}');
      if (!mounted) return;
      setState(
        () =>
            _rows =
                _rows
                    .where((row) => '${row['id']}' != '${reward['id']}')
                    .toList(),
      );
      _message(
        'Reward hidden successfully. Existing redeemed vouchers remain usable.',
      );
    } catch (error) {
      if (mounted) {
        _message(
          friendlyErrorMessage(
            error,
            fallback: 'Could not delete the reward. Please try again.',
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Rewards'),
      actions: [
        IconButton(
          tooltip: 'Refresh rewards',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_outlined),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _create,
      icon: const Icon(Icons.add),
      label: const Text('Create reward'),
    ),
    body:
        _loading && _rows.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _rows.isEmpty
            ? AppStateMessage(
              icon: Icons.card_giftcard_outlined,
              title: 'Could not load rewards',
              message: _error!,
              actionLabel: 'Retry',
              onAction: _refresh,
            )
            : _rows.isEmpty
            ? const Center(child: Text('No rewards have been created yet.'))
            : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
              itemCount: _rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final reward = _rows[index];
                final points =
                    (reward['points_required'] as num?)?.toInt() ?? 0;
                final discount =
                    (reward['discount_myr'] as num?)?.toDouble() ?? 0;
                final minimum =
                    (reward['minimum_spend_myr'] as num?)?.toDouble() ?? 0;
                final active = reward['is_active'] == true;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const CircleAvatar(
                              child: Icon(Icons.card_giftcard_outlined),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${reward['title']}',
                                    style:
                                        Theme.of(context).textTheme.titleSmall,
                                  ),
                                  Text('$points points'),
                                ],
                              ),
                            ),
                            Switch.adaptive(
                              value: active,
                              onChanged: (value) => _setActive(reward, value),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'RM ${discount.toStringAsFixed(2)} discount',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text('Minimum spend: RM ${minimum.toStringAsFixed(2)}'),
                        if ('${reward['description'] ?? ''}'.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text('${reward['description']}'),
                        ],
                        if (!active) ...[
                          const SizedBox(height: 6),
                          const Text('Users cannot redeem this reward.'),
                        ],
                        const Divider(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              onPressed: () => _edit(reward),
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Edit'),
                            ),
                            TextButton.icon(
                              onPressed: () => _delete(reward),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Delete'),
                              style: TextButton.styleFrom(
                                foregroundColor:
                                    Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
  );
}

class _RewardDraft {
  const _RewardDraft({
    required this.title,
    required this.description,
    required this.pointsRequired,
    required this.discountMyr,
    required this.minimumSpendMyr,
  });

  final String title;
  final String description;
  final int pointsRequired;
  final double discountMyr;
  final double minimumSpendMyr;
}

class _RewardEditorDialog extends StatefulWidget {
  const _RewardEditorDialog({this.initial});

  final _RewardDraft? initial;

  @override
  State<_RewardEditorDialog> createState() => _RewardEditorDialogState();
}

class _RewardEditorDialogState extends State<_RewardEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _points;
  late final TextEditingController _discount;
  late final TextEditingController _minimum;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.initial?.title ?? '');
    _description = TextEditingController(
      text: widget.initial?.description ?? '',
    );
    _points = TextEditingController(
      text: widget.initial?.pointsRequired.toString() ?? '',
    );
    _discount = TextEditingController(
      text: widget.initial?.discountMyr.toStringAsFixed(2) ?? '',
    );
    _minimum = TextEditingController(
      text: widget.initial?.minimumSpendMyr.toStringAsFixed(2) ?? '',
    );
    _discount.addListener(_updateMinimum);
  }

  void _updateMinimum() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _discount.removeListener(_updateMinimum);
    _title.dispose();
    _description.dispose();
    _points.dispose();
    _discount.dispose();
    _minimum.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final discount = double.parse(_discount.text);
    final minimum = double.parse(_minimum.text);
    Navigator.pop(
      context,
      _RewardDraft(
        title: _title.text.trim(),
        description: _description.text.trim(),
        pointsRequired: int.parse(_points.text),
        discountMyr: discount,
        minimumSpendMyr: math.max(minimum, discount + 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final discount = double.tryParse(_discount.text) ?? 0;
    final requiredMinimum = discount + 2;
    return AlertDialog(
      title: Text(widget.initial == null ? 'Create reward' : 'Edit reward'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Reward title'),
                  validator:
                      (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Enter a reward title.'
                              : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _description,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _points,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Points required',
                  ),
                  validator:
                      (value) =>
                          int.tryParse(value ?? '') == null ||
                                  int.parse(value!) <= 0
                              ? 'Enter points above zero.'
                              : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _discount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Voucher discount (RM)',
                  ),
                  validator:
                      (value) =>
                          double.tryParse(value ?? '') == null ||
                                  double.parse(value!) <= 0
                              ? 'Enter a discount above zero.'
                              : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _minimum,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Minimum spend (RM)',
                    helperText:
                        'At least RM ${requiredMinimum.toStringAsFixed(2)} is enforced.',
                  ),
                  validator:
                      (value) =>
                          double.tryParse(value ?? '') == null ||
                                  double.parse(value!) < 0
                              ? 'Enter a valid minimum spend.'
                              : null,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.initial == null ? 'Create' : 'Save'),
        ),
      ],
    );
  }
}
