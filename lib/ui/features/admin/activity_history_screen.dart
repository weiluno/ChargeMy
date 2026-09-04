import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/widgets.dart';

class ActivityHistoryScreen extends ConsumerStatefulWidget {
  const ActivityHistoryScreen({super.key});

  @override
  ConsumerState<ActivityHistoryScreen> createState() =>
      _ActivityHistoryScreenState();
}

class _ActivityHistoryScreenState extends ConsumerState<ActivityHistoryScreen> {
  late Future<List<Map<String, dynamic>>> _activities;

  @override
  void initState() {
    super.initState();
    _activities = _load();
  }

  Future<List<Map<String, dynamic>>> _load() =>
      ref.read(stationRepositoryProvider).loadAdminActivity();

  void _reload() => setState(() {
    _activities = _load();
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Admin activity'),
      actions: [
        IconButton(
          tooltip: 'Refresh activity',
          icon: const Icon(Icons.refresh),
          onPressed: _reload,
        ),
      ],
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _activities,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return AppStateMessage(
            icon: Icons.history_toggle_off_outlined,
            title: 'Could not load activity',
            message: friendlyErrorMessage(snapshot.error),
            actionLabel: 'Try again',
            onAction: _reload,
          );
        }
        final activities = snapshot.data ?? const <Map<String, dynamic>>[];
        if (activities.isEmpty) {
          return const AppStateMessage(
            icon: Icons.history_outlined,
            title: 'No activity yet',
            message:
                'Admin changes to stations, piles, tickets, and hazard reports will appear here.',
          );
        }
        final byAdmin = <String, List<Map<String, dynamic>>>{};
        for (final activity in activities) {
          final id = '${activity['admin_id'] ?? 'unknown'}';
          byAdmin.putIfAbsent(id, () => []).add(activity);
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: byAdmin.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final adminId = byAdmin.keys.elementAt(index);
            final adminActivities = byAdmin[adminId]!;
            final adminName =
                '${adminActivities.first['admin_name'] ?? 'Administrator'}';
            return _AdminTile(
              name: adminName,
              activities: adminActivities,
              onTap:
                  () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder:
                          (_) => AdminActivityDetailsScreen(
                            adminName: adminName,
                            activities: adminActivities,
                          ),
                    ),
                  ),
            );
          },
        );
      },
    ),
  );
}

class _AdminTile extends StatelessWidget {
  const _AdminTile({
    required this.name,
    required this.activities,
    required this.onTap,
  });

  final String name;
  final List<Map<String, dynamic>> activities;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final latest = activities.first;
    return Card(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
          child: Icon(
            Icons.manage_accounts_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        title: Text(name),
        subtitle: Text(
          '${activities.length} change${activities.length == 1 ? '' : 's'} · ${latest['action'] ?? 'Updated record'}',
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class AdminActivityDetailsScreen extends StatefulWidget {
  const AdminActivityDetailsScreen({
    super.key,
    required this.adminName,
    required this.activities,
  });

  final String adminName;
  final List<Map<String, dynamic>> activities;

  @override
  State<AdminActivityDetailsScreen> createState() =>
      _AdminActivityDetailsScreenState();
}

class _AdminActivityDetailsScreenState
    extends State<AdminActivityDetailsScreen> {
  String _period = 'today';
  DateTimeRange? _customRange;

  Future<void> _chooseDates() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _customRange,
    );
    if (picked != null && mounted) {
      setState(() {
        _period = 'custom';
        _customRange = picked;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredActivities {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sevenDaysAgo = today.subtract(const Duration(days: 6));
    return widget.activities.where((activity) {
      final date = DateTime.tryParse('${activity['created_at']}')?.toLocal();
      if (date == null) return false;
      final day = DateTime(date.year, date.month, date.day);
      if (_period == 'today') return day == today;
      if (_period == 'week') {
        return !day.isBefore(sevenDaysAgo) && !day.isAfter(today);
      }
      if (_period == 'custom' && _customRange != null) {
        final start = DateTime(
          _customRange!.start.year,
          _customRange!.start.month,
          _customRange!.start.day,
        );
        final end = DateTime(
          _customRange!.end.year,
          _customRange!.end.month,
          _customRange!.end.day,
        );
        return !day.isBefore(start) && !day.isAfter(end);
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final activities = _filteredActivities;
    return Scaffold(
      appBar: AppBar(title: Text(widget.adminName)),
      body: Column(
        children: [
          SizedBox(
            height: 58,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              children: [
                ChoiceChip(
                  label: const Text('Today'),
                  selected: _period == 'today',
                  onSelected: (_) => setState(() => _period = 'today'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Last 7 days'),
                  selected: _period == 'week',
                  onSelected: (_) => setState(() => _period = 'week'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _chooseDates,
                  icon: const Icon(Icons.date_range_outlined, size: 18),
                  label: Text(
                    _period == 'custom' ? 'Selected dates' : 'Choose dates',
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child:
                activities.isEmpty
                    ? const AppStateMessage(
                      icon: Icons.event_busy_outlined,
                      title: 'No changes in this period',
                      message:
                          'Try another date range to view this admin’s activity.',
                    )
                    : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: activities.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder:
                          (context, index) =>
                              _ActivityTile(row: activities[index]),
                    ),
          ),
        ],
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final action = '${row['action'] ?? 'Updated item'}';
    final details =
        (row['details'] as Map?)?.cast<String, dynamic>() ?? const {};
    final station = details['station_name'];
    final pile = details['pile_label'];
    final item =
        station != null && pile != null
            ? '$station · $pile'
            : pile ?? station ?? 'Record ${row['entity_id']}';
    final oldStatus = details['old_status'];
    final newStatus = details['new_status'];
    final statusText =
        oldStatus == null && newStatus == null
            ? null
            : '${oldStatus ?? '—'} → ${newStatus ?? '—'}';
    final date = DateTime.tryParse('${row['created_at']}')?.toLocal();
    final time =
        date == null
            ? 'Recently'
            : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
          child: Icon(
            _iconFor(action),
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        title: Text(action),
        subtitle: Text(
          '$item${statusText == null ? '' : '\n$statusText'}\n$time',
        ),
        isThreeLine: true,
      ),
    );
  }

  IconData _iconFor(String action) {
    final lower = action.toLowerCase();
    if (lower.contains('hazard')) return Icons.report_problem_outlined;
    if (lower.contains('ticket')) return Icons.build_circle_outlined;
    if (lower.contains('station')) return Icons.location_city_outlined;
    return Icons.ev_station_outlined;
  }
}
