import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/charging_models.dart';
import '../../core/app_state.dart';
import '../../core/widgets.dart';

class TicketsScreen extends ConsumerStatefulWidget {
  const TicketsScreen({super.key});

  @override
  ConsumerState<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends ConsumerState<TicketsScreen> {
  late Future<List<MaintenanceTicket>> _tickets;
  final _search = TextEditingController();
  String _statusFilter = 'all';
  bool _searchOpen = false;

  @override
  void initState() {
    super.initState();
    _tickets = _load();
  }

  Future<List<MaintenanceTicket>> _load() =>
      ref.read(stationRepositoryProvider).loadTickets();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _changeTicketStatus(
    MaintenanceTicket ticket,
    String status,
  ) async {
    if (status == ticket.status || ticket.status == 'resolved') return;
    if (status == 'resolved') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: const Text('Resolve this ticket?'),
              content: const Text(
                'Confirm only after the maintenance work is complete. Resolved tickets are final and cannot be changed again.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Keep in progress'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Mark resolved'),
                ),
              ],
            ),
      );
      if (confirmed != true) return;
    }
    try {
      await ref
          .read(stationRepositoryProvider)
          .updateTicketStatus(ticket.id, status);
      if (mounted) {
        setState(() {
          _tickets = _load();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ticket marked ${_statusLabel(status)}.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
      }
    }
  }

  String _statusLabel(String status) => switch (status) {
    'in_progress' => 'in progress',
    'resolved' => 'resolved',
    _ => 'open',
  };

  void _reload() => setState(() {
    _tickets = _load();
  });

  Widget _filterBar() => SizedBox(
    height: 48,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (final status in const ['all', 'open', 'in_progress', 'resolved'])
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(status == 'all' ? 'All' : _statusLabel(status)),
              selected: _statusFilter == status,
              onSelected: (_) => setState(() => _statusFilter = status),
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final stationNames = ref
        .watch(stationsProvider)
        .maybeWhen(
          data:
              (stations) => <String, String>{
                for (final station in stations) station.id: station.name,
              },
          orElse: () => <String, String>{},
        );
    final pileNames = ref
        .watch(stationsProvider)
        .maybeWhen(
          data:
              (stations) => <String, String>{
                for (final station in stations)
                  for (final pile in station.piles) pile.id: pile.label,
              },
          orElse: () => <String, String>{},
        );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Maintenance tickets'),
        actions: [
          IconButton(
            tooltip: _searchOpen ? 'Close ticket search' : 'Search tickets',
            icon: Icon(_searchOpen ? Icons.close : Icons.search),
            onPressed:
                () => setState(() {
                  _searchOpen = !_searchOpen;
                  if (!_searchOpen) _search.clear();
                }),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body:
          !session.isAdmin
              ? const Center(child: Text('Admin access is required.'))
              : FutureBuilder<List<MaintenanceTicket>>(
                future: _tickets,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(friendlyErrorMessage(snapshot.error)),
                    );
                  }
                  final allTickets = snapshot.data ?? const [];
                  if (allTickets.isEmpty) {
                    return const AppStateMessage(
                      icon: Icons.build_circle_outlined,
                      title: 'No maintenance tickets',
                      message:
                          'Three reports for the same pile within 24 hours create a ticket automatically.',
                    );
                  }
                  final query = _search.text.trim().toLowerCase();
                  final tickets =
                      allTickets.where((ticket) {
                        if (_statusFilter != 'all' &&
                            ticket.status != _statusFilter) {
                          return false;
                        }
                        if (query.isEmpty) return true;
                        final station =
                            stationNames[ticket.stationId] ?? ticket.stationId;
                        final pile =
                            ticket.pileId == null
                                ? 'station-wide'
                                : (pileNames[ticket.pileId!] ?? ticket.pileId!);
                        return '$station $pile ${ticket.severity} ${ticket.status}'
                            .toLowerCase()
                            .contains(query);
                      }).toList();
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _filterBar(),
                      if (_searchOpen) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: _search,
                          autofocus: true,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: 'Search station or pile',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                      if (tickets.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: Center(
                            child: Text(
                              'No maintenance tickets match this filter.',
                            ),
                          ),
                        ),
                      for (final ticket in tickets)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor:
                                      ticket.severity == 'high'
                                          ? Theme.of(
                                            context,
                                          ).colorScheme.errorContainer
                                          : Theme.of(
                                            context,
                                          ).colorScheme.secondaryContainer,
                                  child: Icon(
                                    Icons.build_circle_outlined,
                                    color:
                                        ticket.severity == 'high'
                                            ? Theme.of(
                                              context,
                                            ).colorScheme.error
                                            : Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        stationNames[ticket.stationId] ??
                                            ticket.stationId,
                                        style:
                                            Theme.of(
                                              context,
                                            ).textTheme.titleSmall,
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${ticket.reportCount} reports · ${ticket.pileId == null ? 'Station-wide' : (pileNames[ticket.pileId!] ?? ticket.pileId)}',
                                        style:
                                            Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                _TicketStatusMenu(
                                  status: ticket.status,
                                  enabled: ticket.status != 'resolved',
                                  onSelected:
                                      (status) =>
                                          _changeTicketStatus(ticket, status),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
    );
  }
}

class _TicketStatusMenu extends StatelessWidget {
  const _TicketStatusMenu({
    required this.status,
    required this.enabled,
    required this.onSelected,
  });

  final String status;
  final bool enabled;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'resolved' => ('Resolved', Theme.of(context).colorScheme.primary),
      'in_progress' => ('In progress', const Color(0xFFB87500)),
      _ => ('Open', const Color(0xFFB87500)),
    };
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap:
          !enabled
              ? null
              : () async {
                final selected = await showModalBottomSheet<String>(
                  context: context,
                  showDragHandle: true,
                  builder:
                      (sheetContext) => SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Update ticket status',
                                style:
                                    Theme.of(sheetContext).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Choose the current maintenance stage.',
                              ),
                              const SizedBox(height: 12),
                              for (final option in const [
                                ('open', 'Open', 'Awaiting review'),
                                (
                                  'in_progress',
                                  'In progress',
                                  'Work is underway',
                                ),
                                ('resolved', 'Resolved', 'Fixed and verified'),
                              ])
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(
                                    option.$1 == 'resolved'
                                        ? Icons.check_circle_outline
                                        : Icons.build_circle_outlined,
                                  ),
                                  title: Text(option.$2),
                                  subtitle: Text(option.$3),
                                  trailing:
                                      status == option.$1
                                          ? const Icon(Icons.check)
                                          : null,
                                  onTap:
                                      () => Navigator.of(
                                        sheetContext,
                                      ).pop(option.$1),
                                ),
                            ],
                          ),
                        ),
                      ),
                );
                if (selected != null) onSelected(selected);
              },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
              if (enabled) ...[
                const SizedBox(width: 2),
                Icon(Icons.keyboard_arrow_down, color: color, size: 17),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
