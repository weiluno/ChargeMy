import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/widgets.dart';

class VouchersAdminScreen extends ConsumerStatefulWidget {
  const VouchersAdminScreen({super.key});

  @override
  ConsumerState<VouchersAdminScreen> createState() =>
      _VouchersAdminScreenState();
}

class _VouchersAdminScreenState extends ConsumerState<VouchersAdminScreen> {
  List<Map<String, dynamic>> _voucherRows = [];
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _showRows(Iterable<Map<String, dynamic>> rows) {
    final snapshot = rows.map(Map<String, dynamic>.from).toList();
    setState(() => _voucherRows = snapshot);
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final rows =
          await ref.read(stationRepositoryProvider).loadAdminVouchers();
      if (!mounted) return;
      setState(() {
        _voucherRows = rows.map(Map<String, dynamic>.from).toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = friendlyErrorMessage(
          error,
          fallback: 'Could not load vouchers. Please try again.',
        );
      });
    }
  }

  void _message(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _createVoucher() async {
    final draft = await showDialog<_VoucherDraft>(
      context: context,
      builder: (_) => const _VoucherEditorDialog(),
    );
    if (draft == null || !mounted) return;
    late Map<String, dynamic> created;
    try {
      created = await ref
          .read(stationRepositoryProvider)
          .createVoucher(
            code: draft.code,
            title: draft.title,
            description: draft.description,
            discountType: draft.discountType,
            discountValue: draft.discountValue,
            minimumSpendMyr: draft.minimumSpendMyr,
            maxRedemptions: draft.maxRedemptions,
            expiresAt: draft.expiresAt,
          );
    } catch (error) {
      if (mounted) {
        _message(
          friendlyErrorMessage(
            error,
            fallback: 'Could not create the voucher. Please try again.',
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    final index = _voucherRows.lastIndexWhere(
      (voucher) => voucher['is_new_user_voucher'] == true,
    );
    final rows = List<Map<String, dynamic>>.from(_voucherRows);
    rows.insert(index + 1, {...created, 'claim_count': 0, 'redeemed_count': 0});
    _showRows(rows);
    _message('Voucher created successfully.');
  }

  Future<void> _setActive(Map<String, dynamic> voucher, bool isActive) async {
    try {
      await ref
          .read(stationRepositoryProvider)
          .setVoucherActive(voucherId: '${voucher['id']}', isActive: isActive);
    } catch (error) {
      if (mounted) {
        _message(
          friendlyErrorMessage(
            error,
            fallback:
                isActive
                    ? 'Could not activate the voucher. Please try again.'
                    : 'Could not pause the voucher. Please try again.',
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    _showRows(
      _voucherRows.map(
        (row) =>
            '${row['id']}' == '${voucher['id']}'
                ? {...row, 'is_active': isActive}
                : row,
      ),
    );
    _message(
      isActive
          ? 'Voucher activated successfully.'
          : 'Voucher paused successfully.',
    );
  }

  Future<void> _editVoucher(Map<String, dynamic> voucher) async {
    final draft = await showDialog<_VoucherDraft>(
      context: context,
      builder: (_) => _VoucherEditorDialog(initial: _draftFrom(voucher)),
    );
    if (draft == null || !mounted) return;
    late Map<String, dynamic> updated;
    try {
      updated = await ref
          .read(stationRepositoryProvider)
          .updateVoucher(
            voucherId: '${voucher['id']}',
            code: draft.code,
            title: draft.title,
            description: draft.description,
            discountType: draft.discountType,
            discountValue: draft.discountValue,
            minimumSpendMyr: draft.minimumSpendMyr,
            maxRedemptions: draft.maxRedemptions,
            expiresAt: draft.expiresAt,
          );
    } catch (error) {
      if (mounted) {
        _message(
          friendlyErrorMessage(
            error,
            fallback: 'Could not update the voucher. Please try again.',
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    _showRows(
      _voucherRows.map(
        (row) =>
            '${row['id']}' == '${voucher['id']}' ? {...row, ...updated} : row,
      ),
    );
    _message('Voucher updated successfully.');
  }

  Future<void> _deleteVoucher(Map<String, dynamic> voucher) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Delete voucher?'),
            content: Text(
              'Delete ${voucher['code']}? Users will no longer be able to claim or use it.',
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
      await ref
          .read(stationRepositoryProvider)
          .deleteVoucher('${voucher['id']}');
    } catch (error) {
      if (mounted) {
        _message(
          friendlyErrorMessage(
            error,
            fallback: 'Could not delete the voucher. Please try again.',
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    _showRows(
      _voucherRows.where((row) => '${row['id']}' != '${voucher['id']}'),
    );
    _message('Voucher deleted successfully.');
  }

  _VoucherDraft _draftFrom(Map<String, dynamic> voucher) => _VoucherDraft(
    code: '${voucher['code']}',
    title: '${voucher['title']}',
    description: '${voucher['description'] ?? ''}',
    discountType: '${voucher['discount_type']}',
    discountValue: (voucher['discount_value'] as num?)?.toDouble() ?? 0,
    minimumSpendMyr: (voucher['minimum_spend_myr'] as num?)?.toDouble() ?? 0,
    maxRedemptions: (voucher['max_redemptions'] as num?)?.toInt(),
    expiresAt: DateTime.tryParse('${voucher['expires_at']}')?.toLocal(),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Vouchers'),
      actions: [
        IconButton(
          tooltip: 'Refresh vouchers',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_outlined),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _createVoucher,
      icon: const Icon(Icons.add),
      label: const Text('Create voucher'),
    ),
    body:
        _loading && _voucherRows.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null && _voucherRows.isEmpty
            ? AppStateMessage(
              icon: Icons.confirmation_number_outlined,
              title: 'Could not load vouchers',
              message: _loadError!,
              actionLabel: 'Retry',
              onAction: _refresh,
            )
            : _voucherRows.isEmpty
            ? const Center(child: Text('No vouchers have been created yet.'))
            : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
              itemCount: _voucherRows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final voucher = _voucherRows[index];
                return _VoucherAdminCard(
                  key: ValueKey('${voucher['id']}-${voucher['updated_at']}'),
                  voucher: voucher,
                  onActiveChanged: (value) => _setActive(voucher, value),
                  onEdit: () => _editVoucher(voucher),
                  onDelete: () => _deleteVoucher(voucher),
                );
              },
            ),
  );
}

class _VoucherAdminCard extends StatelessWidget {
  const _VoucherAdminCard({
    super.key,
    required this.voucher,
    required this.onActiveChanged,
    required this.onEdit,
    required this.onDelete,
  });

  final Map<String, dynamic> voucher;
  final ValueChanged<bool> onActiveChanged;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isActive = voucher['is_active'] == true;
    final isSystem = voucher['is_new_user_voucher'] == true;
    final discountValue = (voucher['discount_value'] as num?)?.toDouble() ?? 0;
    final isPercent = voucher['discount_type'] == 'percent';
    final storedMinimum =
        (voucher['minimum_spend_myr'] as num?)?.toDouble() ?? 0;
    final minimum =
        isPercent ? storedMinimum : math.max(storedMinimum, discountValue + 2);
    final claims = voucher['claim_count'] ?? 0;
    final redeemed = voucher['redeemed_count'] ?? 0;
    final expiry = DateTime.tryParse('${voucher['expires_at']}')?.toLocal();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  child: const Icon(Icons.local_offer_outlined),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${voucher['title']}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        '${voucher['code']}',
                        style: const TextStyle(letterSpacing: 1.1),
                      ),
                    ],
                  ),
                ),
                if (isSystem)
                  const Chip(label: Text('New user'))
                else
                  Switch.adaptive(value: isActive, onChanged: onActiveChanged),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              isPercent
                  ? '${discountValue.toStringAsFixed(0)}% discount'
                  : 'RM ${discountValue.toStringAsFixed(2)} discount',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text('Minimum spend: RM ${minimum.toStringAsFixed(2)}'),
            if ('${voucher['description'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('${voucher['description']}'),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: Text('$claims claimed · $redeemed redeemed')),
                Text(
                  expiry == null
                      ? 'No expiry'
                      : 'Expires ${MaterialLocalizations.of(context).formatMediumDate(expiry)}',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
            if (!isSystem && !isActive)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('This voucher is paused.'),
              ),
            if (!isSystem) ...[
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _VoucherDraft {
  const _VoucherDraft({
    required this.code,
    required this.title,
    required this.description,
    required this.discountType,
    required this.discountValue,
    required this.minimumSpendMyr,
    this.maxRedemptions,
    this.expiresAt,
  });

  final String code;
  final String title;
  final String description;
  final String discountType;
  final double discountValue;
  final double minimumSpendMyr;
  final int? maxRedemptions;
  final DateTime? expiresAt;
}

class _VoucherEditorDialog extends StatefulWidget {
  const _VoucherEditorDialog({this.initial});

  final _VoucherDraft? initial;

  @override
  State<_VoucherEditorDialog> createState() => _VoucherEditorDialogState();
}

class _VoucherEditorDialogState extends State<_VoucherEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _discount;
  late final TextEditingController _minimum;
  late final TextEditingController _limit;
  late String _type;
  DateTime? _expiry;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _code = TextEditingController(text: initial?.code ?? '');
    _title = TextEditingController(text: initial?.title ?? '');
    _description = TextEditingController(text: initial?.description ?? '');
    _discount = TextEditingController(
      text: initial?.discountValue.toStringAsFixed(2) ?? '',
    );
    _minimum = TextEditingController(
      text: initial?.minimumSpendMyr.toStringAsFixed(2) ?? '0',
    );
    _limit = TextEditingController(
      text: initial?.maxRedemptions?.toString() ?? '',
    );
    _type = initial?.discountType ?? 'fixed';
    _expiry = initial?.expiresAt;
  }

  @override
  void dispose() {
    _code.dispose();
    _title.dispose();
    _description.dispose();
    _discount.dispose();
    _minimum.dispose();
    _limit.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final firstDate = DateUtils.dateOnly(
      DateTime.now().add(const Duration(days: 1)),
    );
    final lastDate = DateUtils.dateOnly(
      DateTime.now().add(const Duration(days: 3650)),
    );
    final currentExpiry = _expiry == null ? null : DateUtils.dateOnly(_expiry!);
    final date = await showDatePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDate:
          currentExpiry != null &&
                  !currentExpiry.isBefore(firstDate) &&
                  !currentExpiry.isAfter(lastDate)
              ? currentExpiry
              : firstDate.add(const Duration(days: 30)),
    );
    if (date != null) {
      setState(
        () => _expiry = DateTime(date.year, date.month, date.day, 23, 59, 59),
      );
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _VoucherDraft(
        code: _code.text,
        title: _title.text,
        description: _description.text,
        discountType: _type,
        discountValue: double.parse(_discount.text),
        minimumSpendMyr:
            _type == 'fixed'
                ? math.max(
                  double.parse(_minimum.text),
                  double.parse(_discount.text) + 2,
                )
                : double.parse(_minimum.text),
        maxRedemptions: int.tryParse(_limit.text),
        expiresAt: _expiry,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460, maxHeight: 680),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  child: const Icon(Icons.local_offer_outlined),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.initial == null ? 'Create voucher' : 'Edit voucher',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.initial == null
                    ? 'Set the code, discount and optional limits.'
                    : 'Update the voucher details and availability.',
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _code,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Voucher code',
                          hintText: 'Example: SAVE5',
                          prefixIcon: Icon(Icons.code_outlined),
                        ),
                        validator:
                            (value) =>
                                value == null || value.trim().length < 3
                                    ? 'Enter at least 3 characters.'
                                    : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _title,
                        decoration: const InputDecoration(
                          labelText: 'Voucher title',
                          hintText: 'Example: Weekend special',
                        ),
                        validator:
                            (value) =>
                                value == null || value.trim().isEmpty
                                    ? 'Enter a title.'
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
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Discount details',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _type,
                        decoration: const InputDecoration(
                          labelText: 'Discount type',
                          prefixIcon: Icon(Icons.discount_outlined),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'fixed',
                            child: Text('Fixed RM amount'),
                          ),
                          DropdownMenuItem(
                            value: 'percent',
                            child: Text('Percentage'),
                          ),
                        ],
                        onChanged:
                            (value) => setState(() => _type = value ?? 'fixed'),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _discount,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText:
                                    _type == 'percent'
                                        ? 'Discount (%)'
                                        : 'Discount (RM)',
                              ),
                              validator:
                                  (value) =>
                                      double.tryParse(value ?? '') == null ||
                                              double.parse(value!) <= 0
                                          ? 'Enter a value above zero.'
                                          : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _minimum,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Minimum spend (RM)',
                              ),
                              validator:
                                  (value) =>
                                      double.tryParse(value ?? '') == null ||
                                              double.parse(value!) < 0
                                          ? 'Enter a valid amount.'
                                          : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Availability',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _limit,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Claim limit (optional)',
                          hintText: 'Leave empty for no limit',
                        ),
                        validator:
                            (value) =>
                                value == null ||
                                        value.isEmpty ||
                                        (int.tryParse(value) != null &&
                                            int.parse(value) > 0)
                                    ? null
                                    : 'Enter a whole number above zero.',
                      ),
                      const SizedBox(height: 8),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.event_outlined),
                        title: Text(
                          _expiry == null
                              ? 'No expiry date'
                              : 'Expires ${MaterialLocalizations.of(context).formatMediumDate(_expiry!)}',
                        ),
                        trailing: TextButton(
                          onPressed: _pickExpiry,
                          child: Text(
                            _expiry == null ? 'Set expiry' : 'Change',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.add),
                    label: Text(
                      widget.initial == null ? 'Create' : 'Save changes',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
