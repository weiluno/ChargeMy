import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/charging_models.dart';
import '../../core/app_state.dart';
import '../../core/csv_export.dart';
import '../../core/widgets.dart';

class RevenueScreen extends ConsumerStatefulWidget {
  const RevenueScreen({super.key});

  @override
  ConsumerState<RevenueScreen> createState() => _RevenueScreenState();
}

class _RevenueScreenState extends ConsumerState<RevenueScreen> {
  late Future<List<Map<String, dynamic>>> _rows;
  late Future<List<Map<String, dynamic>>> _transactions;
  final _transactionSearch = TextEditingController();
  bool _searchOpen = false;
  String _dateFilter = 'week';
  DateTimeRange? _customDateRange;

  @override
  void initState() {
    super.initState();
    _rows = ref.read(stationRepositoryProvider).loadRevenueAnalytics();
    _transactions =
        ref.read(stationRepositoryProvider).loadRevenueTransactions();
  }

  @override
  void dispose() {
    _transactionSearch.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _rows = ref.read(stationRepositoryProvider).loadRevenueAnalytics();
      _transactions =
          ref.read(stationRepositoryProvider).loadRevenueTransactions();
    });
  }

  Future<void> _selectDateFilter(String value) async {
    if (value != 'custom') {
      setState(() => _dateFilter = value);
      return;
    }
    final today = DateUtils.dateOnly(DateTime.now());
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: today,
      initialDateRange:
          _customDateRange ??
          DateTimeRange(
            start: today.subtract(const Duration(days: 6)),
            end: today,
          ),
      helpText: 'Select session date range',
    );
    if (!mounted || selected == null) return;
    setState(() {
      _dateFilter = 'custom';
      _customDateRange = selected;
    });
  }

  List<Map<String, dynamic>> _filterByDate(List<Map<String, dynamic>> rows) {
    final today = DateUtils.dateOnly(DateTime.now());
    final startOfWeek = today.subtract(const Duration(days: 6));
    final startOfMonth = today.subtract(const Duration(days: 29));
    return rows.where((row) {
      final date = DateTime.tryParse('${row['day'] ?? ''}');
      if (date == null) return false;
      final day = DateUtils.dateOnly(date);
      if (_dateFilter == 'today') return day == today;
      if (_dateFilter == 'week') {
        return !day.isBefore(startOfWeek) && !day.isAfter(today);
      }
      if (_dateFilter == 'month') {
        return !day.isBefore(startOfMonth) && !day.isAfter(today);
      }
      final range = _customDateRange;
      if (range == null) return true;
      final from = DateUtils.dateOnly(range.start);
      final to = DateUtils.dateOnly(range.end);
      return !day.isBefore(from) && !day.isAfter(to);
    }).toList();
  }

  Future<void> _export(List<Map<String, dynamic>> rows) async {
    final lines = <String>['day,station,paid_sessions,energy_kwh,revenue_myr'];
    for (final row in rows) {
      lines.add(
        [
          csvCell(row['day']),
          csvCell(
            cleanDisplayText(
              '${row['station_name'] ?? row['station_id']}',
              fallback: 'Charging station',
            ),
          ),
          csvCell(row['paid_sessions']),
          csvCell(
            ((row['energy_kwh'] as num?)?.toDouble() ?? 0).toStringAsFixed(2),
          ),
          csvCell(
            ((row['revenue_myr'] as num?)?.toDouble() ?? 0).toStringAsFixed(2),
          ),
        ].join(','),
      );
    }
    final saved = await saveCsvFile(
      fileName: 'chargemy_revenue_${DateTime.now().millisecondsSinceEpoch}.csv',
      content: lines.join('\n'),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved ? 'Revenue CSV saved successfully.' : 'CSV export cancelled.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Revenue report'),
      actions: [
        IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
      ],
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _rows,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                friendlyErrorMessage(
                  snapshot.error,
                  fallback:
                      'Revenue data is temporarily unavailable. Please try again later.',
                ),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final allRows = snapshot.data ?? const <Map<String, dynamic>>[];
        final rows = _filterByDate(allRows);
        final revenue = rows.fold<double>(
          0,
          (sum, row) => sum + ((row['revenue_myr'] as num?)?.toDouble() ?? 0),
        );
        final energy = rows.fold<double>(
          0,
          (sum, row) => sum + ((row['energy_kwh'] as num?)?.toDouble() ?? 0),
        );
        final sessions = rows.fold<int>(
          0,
          (sum, row) => sum + ((row['paid_sessions'] as num?)?.toInt() ?? 0),
        );
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: _Summary(
                    label: 'Revenue',
                    value: 'RM ${revenue.toStringAsFixed(2)}',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Summary(label: 'Sessions', value: '$sessions'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _Summary(
                    label: 'Energy sold',
                    value: '${energy.toStringAsFixed(2)} kWh',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: rows.isEmpty ? null : () => _export(rows),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Export CSV'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _transactions,
              builder: (context, transactionSnapshot) {
                if (transactionSnapshot.connectionState !=
                    ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (transactionSnapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      friendlyErrorMessage(
                        transactionSnapshot.error,
                        fallback:
                            'Transaction details are temporarily unavailable.',
                      ),
                    ),
                  );
                }
                final query = _transactionSearch.text.trim().toLowerCase();
                final transactions = transactionSnapshot.data ?? const [];
                final filteredRows =
                    rows.where((row) {
                      if (query.isEmpty) return true;
                      final station =
                          cleanDisplayText(
                            '${row['station_name'] ?? row['station_id']}',
                            fallback: 'Charging station',
                          ).toLowerCase();
                      return station.contains(query) ||
                          transactions.any(
                            (transaction) =>
                                _belongsToSummary(row, transaction) &&
                                _transactionMatches(transaction, query),
                          );
                    }).toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Session period',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 42,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _PeriodChip(
                            label: 'Today',
                            selected: _dateFilter == 'today',
                            onSelected: () => _selectDateFilter('today'),
                          ),
                          _PeriodChip(
                            label: 'Last 7 days',
                            selected: _dateFilter == 'week',
                            onSelected: () => _selectDateFilter('week'),
                          ),
                          _PeriodChip(
                            label: 'Last 30 days',
                            selected: _dateFilter == 'month',
                            onSelected: () => _selectDateFilter('month'),
                          ),
                          _PeriodChip(
                            label: 'More filters',
                            icon: Icons.date_range_outlined,
                            selected: _dateFilter == 'custom',
                            onSelected: () => _selectDateFilter('custom'),
                          ),
                          IconButton(
                            tooltip:
                                _searchOpen
                                    ? 'Close station search'
                                    : 'Search stations',
                            onPressed:
                                () => setState(() {
                                  _searchOpen = !_searchOpen;
                                  if (!_searchOpen) _transactionSearch.clear();
                                }),
                            icon: Icon(
                              _searchOpen ? Icons.close : Icons.search,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_searchOpen) ...[
                      TextField(
                        controller: _transactionSearch,
                        autofocus: true,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search station or session details',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    Text(
                      'Daily summary',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (filteredRows.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('No matching transactions.'),
                        ),
                      )
                    else
                      for (final row in filteredRows)
                        _DailySummaryTile(
                          row: row,
                          transactions:
                              transactions
                                  .where(
                                    (transaction) =>
                                        _belongsToSummary(row, transaction) &&
                                        (query.isEmpty ||
                                            _transactionMatches(
                                              transaction,
                                              query,
                                            )),
                                  )
                                  .toList(),
                          onTransactionTap: _showTransactionDetails,
                          number: _number,
                          formatDateTime: _formatDateTime,
                        ),
                  ],
                );
              },
            ),
          ],
        );
      },
    ),
  );

  void _showTransactionDetails(
    BuildContext context,
    Map<String, dynamic> transaction,
  ) {
    showDialog<void>(
      context: context,
      builder:
          (dialogContext) => Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor:
                              Theme.of(
                                dialogContext,
                              ).colorScheme.primaryContainer,
                          child: const Icon(Icons.receipt_long_outlined),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${transaction['station_name'] ?? transaction['station_id']}',
                            style: Theme.of(dialogContext).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color:
                            Theme.of(
                              dialogContext,
                            ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Payment receipt',
                            style: Theme.of(dialogContext).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 12),
                          _TransactionDetailRow(
                            icon: Icons.person_outline,
                            label: 'User',
                            value:
                                '${transaction['user_email'] ?? 'ChargeMY user'}',
                          ),
                          _TransactionDetailRow(
                            icon: Icons.ev_station_outlined,
                            label: 'Charging pile',
                            value:
                                '${transaction['pile_label'] ?? transaction['pile_id'] ?? 'Unavailable'}',
                          ),
                          _TransactionDetailRow(
                            icon: Icons.schedule_outlined,
                            label: 'Paid at',
                            value: _formatDateTime(transaction['paid_at']),
                          ),
                          _TransactionDetailRow(
                            icon: Icons.bolt_outlined,
                            label: 'Energy delivered',
                            value: '${_number(transaction['energy_kwh'])} kWh',
                          ),
                          _TransactionDetailRow(
                            icon: Icons.battery_charging_full_outlined,
                            label: 'Battery',
                            value:
                                '${transaction['start_soc'] ?? '--'}% → ${transaction['end_soc'] ?? '--'}%',
                          ),
                          const Divider(height: 28),
                          Row(
                            children: [
                              Text(
                                'Amount paid',
                                style:
                                    Theme.of(
                                      dialogContext,
                                    ).textTheme.titleMedium,
                              ),
                              const Spacer(),
                              Text(
                                'RM ${_number(transaction['amount_myr'])}',
                                style: Theme.of(dialogContext)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  bool _belongsToSummary(
    Map<String, dynamic> summary,
    Map<String, dynamic> transaction,
  ) {
    final summaryText = '${summary['day']}';
    final summaryDay =
        summaryText.length >= 10 ? summaryText.substring(0, 10) : summaryText;
    final paidAt = '${transaction['paid_at'] ?? ''}';
    final transactionDay = paidAt.length >= 10 ? paidAt.substring(0, 10) : '';
    return '${summary['station_id']}' == '${transaction['station_id']}' &&
        summaryDay == transactionDay;
  }

  bool _transactionMatches(Map<String, dynamic> transaction, String query) => [
    transaction['station_name'],
    transaction['user_email'],
    transaction['display_name'],
    transaction['pile_id'],
    transaction['pile_label'],
    transaction['session_id'],
  ].any((value) => '${value ?? ''}'.toLowerCase().contains(query));

  String _number(Object? value) =>
      ((value as num?)?.toDouble() ?? 0).toStringAsFixed(2);

  String _formatDateTime(Object? value) {
    if (value == null || '$value' == 'null') return 'Not recorded';
    final date = DateTime.tryParse('$value')?.toLocal();
    if (date == null) return '$value';
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: Theme.of(context).textTheme.titleLarge),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    ),
  );
}

class _TransactionDetailRow extends StatelessWidget {
  const _TransactionDetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 13),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 2),
              Text(value, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    ),
  );
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      selected: selected,
      onSelected: (_) => onSelected(),
      avatar: icon == null ? null : Icon(icon, size: 18),
      label: Text(label),
    ),
  );
}

class _DailySummaryTile extends StatelessWidget {
  const _DailySummaryTile({
    required this.row,
    required this.transactions,
    required this.onTransactionTap,
    required this.number,
    required this.formatDateTime,
  });

  final Map<String, dynamic> row;
  final List<Map<String, dynamic>> transactions;
  final void Function(BuildContext, Map<String, dynamic>) onTransactionTap;
  final String Function(Object?) number;
  final String Function(Object?) formatDateTime;

  @override
  Widget build(BuildContext context) {
    final station = cleanDisplayText(
      '${row['station_name'] ?? row['station_id']}',
      fallback: 'Charging station',
    );
    final sessions = (row['paid_sessions'] as num?)?.toInt() ?? 0;
    final energy = (row['energy_kwh'] as num?)?.toDouble() ?? 0;
    final revenue = (row['revenue_myr'] as num?)?.toDouble() ?? 0;
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.payments_outlined),
        title: Text(station),
        subtitle: Text(
          '${row['day']} · $sessions session(s) · ${energy.toStringAsFixed(2)} kWh',
        ),
        trailing: Text(
          'RM ${revenue.toStringAsFixed(2)}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        children: [
          if (transactions.isEmpty)
            const ListTile(
              dense: true,
              title: Text('No matching transaction details.'),
            )
          else
            for (final transaction in transactions)
              ListTile(
                dense: true,
                onTap: () => onTransactionTap(context, transaction),
                leading: const Icon(Icons.receipt_long_outlined, size: 20),
                title: Text(
                  '${transaction['user_email'] ?? 'ChargeMY user'} · '
                  '${transaction['pile_label'] ?? transaction['pile_id'] ?? 'Pile unavailable'}',
                ),
                subtitle: Text(
                  '${formatDateTime(transaction['paid_at'])} · '
                  '${number(transaction['energy_kwh'])} kWh',
                ),
                trailing: Text(
                  'RM ${number(transaction['amount_myr'])}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
        ],
      ),
    );
  }
}
