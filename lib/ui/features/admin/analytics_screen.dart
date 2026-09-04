import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/charging_models.dart';
import '../../core/app_state.dart';
import '../../core/csv_export.dart';
import '../../core/widgets.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  late Future<List<StationDailyAnalytics>> _summary;
  late Future<List<Map<String, dynamic>>> _maintenance;
  final _stationSearch = TextEditingController();
  bool _searchOpen = false;

  @override
  void initState() {
    super.initState();
    _summary = ref.read(stationRepositoryProvider).loadDailyAnalytics();
    _maintenance =
        ref.read(stationRepositoryProvider).loadMaintenanceCandidates();
  }

  @override
  void dispose() {
    _stationSearch.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _summary = ref.read(stationRepositoryProvider).loadDailyAnalytics();
      _maintenance =
          ref.read(stationRepositoryProvider).loadMaintenanceCandidates();
    });
  }

  Future<void> _export(
    List<StationDailyAnalytics> records,
    Map<String, ChargingStation> stationById,
  ) async {
    final lines = <String>[
      'day,station,completed_sessions,average_stay_minutes',
    ];
    for (final item in records) {
      final station = cleanDisplayText(
        stationById[item.stationId]?.name ?? item.stationId,
        fallback: 'Charging station',
      );
      lines.add(
        [
          csvCell(_date(item.day)),
          csvCell(station),
          csvCell(item.completedSessions),
          csvCell(item.averageStayMinutes?.toStringAsFixed(2) ?? ''),
        ].join(','),
      );
    }
    final saved = await saveCsvFile(
      fileName:
          'chargemy_analytics_${DateTime.now().millisecondsSinceEpoch}.csv',
      content: lines.join('\n'),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved
                ? 'Analytics CSV saved successfully.'
                : 'CSV export cancelled.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final stationState = ref.watch(stationsProvider);
    final stationById = stationState.maybeWhen(
      data:
          (items) => <String, ChargingStation>{
            for (final station in items) station.id: station,
          },
      orElse: () => <String, ChargingStation>{},
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Utilization analytics'),
        actions: [
          IconButton(
            tooltip: _searchOpen ? 'Close station search' : 'Search stations',
            onPressed:
                () => setState(() {
                  _searchOpen = !_searchOpen;
                  if (!_searchOpen) _stationSearch.clear();
                }),
            icon: Icon(_searchOpen ? Icons.close : Icons.search),
          ),
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<List<StationDailyAnalytics>>(
        future: _summary,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(error: snapshot.error, onRetry: _reload);
          }
          final records = snapshot.data ?? const [];
          if (records.isEmpty) {
            return const _EmptyState();
          }
          final completed = records.fold<int>(
            0,
            (total, item) => total + item.completedSessions,
          );
          final durations =
              records
                  .map((item) => item.averageStayMinutes)
                  .whereType<double>()
                  .toList();
          final average =
              durations.isEmpty
                  ? null
                  : durations.reduce((a, b) => a + b) / durations.length;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Charging utilization',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              const Text('Derived from completed in-app charging sessions.'),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _Metric(
                      label: 'Completed charges',
                      value: '$completed',
                      icon: Icons.bolt_outlined,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Metric(
                      label: 'Average stay',
                      value: average == null ? '--' : '${average.round()} min',
                      icon: Icons.timer_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _export(records, stationById),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Export analytics CSV'),
              ),
              const SizedBox(height: 14),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _maintenance,
                builder: (context, maintenanceSnapshot) {
                  final candidates = maintenanceSnapshot.data ?? const [];
                  if (candidates.isEmpty) return const SizedBox.shrink();
                  return InkWell(
                    onTap:
                        () => _showMaintenanceCandidates(
                          context,
                          candidates,
                          stationById,
                        ),
                    borderRadius: BorderRadius.circular(14),
                    child: Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.warning_amber_outlined,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${candidates.length} pile(s) have been in use for more than 200 hours. Tap to review.',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 26),
              if (_searchOpen) ...[
                TextField(
                  controller: _stationSearch,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search station name or ID',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                'Daily station summary',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (final item in records.where((item) {
                final query = _stationSearch.text.trim().toLowerCase();
                if (query.isEmpty) return true;
                final stationName = stationById[item.stationId]?.name ?? '';
                return item.stationId.toLowerCase().contains(query) ||
                    stationName.toLowerCase().contains(query);
              }))
                Card(
                  child: ListTile(
                    onTap:
                        () => _showStationDetails(
                          context,
                          stationById[item.stationId],
                          item,
                        ),
                    leading: CircleAvatar(
                      child: Text('${item.completedSessions}'),
                    ),
                    title: Text(
                      stationById[item.stationId]?.name ?? item.stationId,
                    ),
                    subtitle: Text(
                      _stationSubtitle(item, stationById[item.stationId]),
                    ),
                    trailing: const Icon(Icons.insights_outlined),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  String _stationSubtitle(
    StationDailyAnalytics item,
    ChargingStation? station,
  ) {
    final activePiles =
        station?.piles
            .where(
              (pile) =>
                  pile.status == PileStatus.occupied ||
                  pile.status == PileStatus.reserved,
            )
            .map((pile) => pile.label)
            .toList();
    final pileText =
        activePiles == null || activePiles.isEmpty
            ? 'No active piles now'
            : 'Using: ${activePiles.join(', ')}';
    return '${_date(item.day)}  •  ${item.averageStayMinutes?.round() ?? '--'} min average stay\n$pileText';
  }

  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

  void _showStationDetails(
    BuildContext context,
    ChargingStation? station,
    StationDailyAnalytics item,
  ) {
    if (station == null) return;
    showDialog<void>(
      context: context,
      builder:
          (dialogContext) => Dialog(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 440,
                maxHeight: MediaQuery.sizeOf(dialogContext).height * .78,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor:
                              Theme.of(
                                dialogContext,
                              ).colorScheme.primaryContainer,
                          child: Icon(
                            Icons.ev_station_outlined,
                            color: Theme.of(dialogContext).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text(
                            station.name,
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
                    const SizedBox(height: 8),
                    Text(
                      station.address,
                      style: Theme.of(dialogContext).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color:
                            Theme.of(
                              dialogContext,
                            ).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          _DialogMetric(label: 'Date', value: _date(item.day)),
                          const SizedBox(width: 18),
                          _DialogMetric(
                            label: 'Sessions',
                            value: '${item.completedSessions}',
                          ),
                          const SizedBox(width: 18),
                          _DialogMetric(
                            label: 'Avg. stay',
                            value:
                                '${item.averageStayMinutes?.round() ?? '--'} min',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Charging piles',
                      style: Theme.of(dialogContext).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.separated(
                        itemCount: station.piles.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, index) {
                          final pile = station.piles[index];
                          return DecoratedBox(
                            decoration: BoxDecoration(
                              color:
                                  Theme.of(
                                    dialogContext,
                                  ).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.bolt_outlined, size: 19),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          pile.label,
                                          style:
                                              Theme.of(
                                                dialogContext,
                                              ).textTheme.titleSmall,
                                        ),
                                        Text(
                                          '${pile.connectorType} · ${pile.powerKw.toStringAsFixed(2)} kW',
                                          style:
                                              Theme.of(
                                                dialogContext,
                                              ).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  StatusPill(status: pile.status),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  void _showMaintenanceCandidates(
    BuildContext context,
    List<Map<String, dynamic>> candidates,
    Map<String, ChargingStation> stationById,
  ) {
    showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Maintenance attention'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'These piles have been in use for more than 200 hours.',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Recommended action: inspect the connector, cable, physical bay and charger logs. If a fault is found, set the pile to Maintenance. Otherwise mark this alert completed after inspection.',
                  ),
                  const SizedBox(height: 10),
                  for (final candidate in candidates)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.warning_amber_outlined),
                      title: Text(
                        '${stationById['${candidate['station_id']}']?.name ?? candidate['station_id']}',
                      ),
                      subtitle: Text(
                        '${_pileName(stationById['${candidate['station_id']}'], '${candidate['pile_id']}')} · ${_occupiedDuration(candidate['started_at'])}',
                      ),
                      trailing: TextButton(
                        onPressed:
                            () => _markMaintenanceCandidateCompleted(
                              dialogContext,
                              '${candidate['pile_id']}',
                            ),
                        child: const Text('Mark completed'),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }

  Future<void> _markMaintenanceCandidateCompleted(
    BuildContext dialogContext,
    String pileId,
  ) async {
    try {
      await ref
          .read(stationRepositoryProvider)
          .markMaintenanceCandidateCompleted(pileId);
      if (!mounted || !dialogContext.mounted) return;
      Navigator.of(dialogContext).pop();
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maintenance alert marked completed.')),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not update this maintenance alert. Please try again.',
            ),
          ),
        );
      }
    }
  }

  String _pileName(ChargingStation? station, String pileId) {
    if (station != null) {
      for (final pile in station.piles) {
        if (pile.id == pileId) return pile.label;
      }
    }
    return pileId;
  }

  String _occupiedDuration(Object? startedAt) {
    final started = DateTime.tryParse('$startedAt')?.toLocal();
    if (started == null) return 'duration unavailable';
    final duration = DateTime.now().difference(started);
    return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m occupied';
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    ),
  );
}

class _DialogMetric extends StatelessWidget {
  const _DialogMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 3),
        Text(value, style: Theme.of(context).textTheme.titleSmall),
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.bar_chart_outlined, size: 48),
          SizedBox(height: 12),
          Text('No completed charge sessions yet.'),
          SizedBox(height: 6),
          Text(
            'Start and complete a charging session to create utilization data.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 12),
          const Text('Could not load utilization analytics.'),
          const SizedBox(height: 6),
          Text(friendlyErrorMessage(error), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}
