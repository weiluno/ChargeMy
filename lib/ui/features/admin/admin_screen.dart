import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../../domain/models/charging_models.dart';
import '../../core/app_state.dart';
import '../../core/widgets.dart';

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key, this.focusStationId, this.focusPileId});

  final String? focusStationId;
  final String? focusPileId;

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  String stationQuery = '';

  @override
  Widget build(BuildContext context) {
    final admin = ref.watch(sessionProvider);
    final stations = ref.watch(stationsProvider);
    if (!admin.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin dashboard')),
        body: Center(
          child: FilledButton(
            onPressed: () => context.push('/auth'),
            child: const Text('Admin sign in required'),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin dashboard'),
        actions: [
          IconButton(
            tooltip: 'Return to profile',
            onPressed: () => context.go('/profile'),
            icon: const Icon(Icons.exit_to_app_outlined),
          ),
        ],
      ),
      body: stations.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:
            (error, _) => AppStateMessage(
              icon: Icons.dashboard_outlined,
              title: 'Could not load the dashboard',
              message: friendlyErrorMessage(
                error,
                fallback: 'Please check your connection and try again.',
              ),
              actionLabel: 'Retry',
              onAction: () => ref.invalidate(stationsProvider),
            ),
        data: (items) {
          final query = stationQuery.trim().toLowerCase();
          final stationItems =
              items.where((station) {
                if (widget.focusStationId != null &&
                    station.id != widget.focusStationId) {
                  return false;
                }
                if (query.isEmpty) return true;
                return station.name.toLowerCase().contains(query) ||
                    station.address.toLowerCase().contains(query) ||
                    station.brand.toLowerCase().contains(query) ||
                    station.localAuthority.toLowerCase().contains(query);
              }).toList();
          final piles = items.expand((station) => station.piles).toList();
          final available =
              piles.where((pile) => pile.status == PileStatus.available).length;
          final active =
              piles
                  .where(
                    (pile) =>
                        pile.status == PileStatus.reserved ||
                        pile.status == PileStatus.occupied,
                  )
                  .length;
          final unavailable =
              piles
                  .where(
                    (pile) =>
                        pile.status == PileStatus.offline ||
                        pile.status == PileStatus.maintenance,
                  )
                  .length;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                childAspectRatio: 1.7,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                children: [
                  _MetricCard(
                    label: 'Available piles',
                    value: '$available',
                    icon: Icons.ev_station_outlined,
                    onTap:
                        () => _showPileStatusDetails(
                          context,
                          'Available piles',
                          items,
                          piles
                              .where(
                                (pile) => pile.status == PileStatus.available,
                              )
                              .toList(),
                        ),
                  ),
                  _MetricCard(
                    label: 'Active piles',
                    value: '$active',
                    icon: Icons.bolt_outlined,
                    onTap:
                        () => _showPileStatusDetails(
                          context,
                          'Active piles',
                          items,
                          piles
                              .where(
                                (pile) =>
                                    pile.status == PileStatus.occupied ||
                                    pile.status == PileStatus.reserved,
                              )
                              .toList(),
                        ),
                  ),
                  _MetricCard(
                    label: 'Offline / maintenance',
                    value: '$unavailable',
                    icon: Icons.warning_amber_outlined,
                    onTap:
                        () => _showPileStatusDetails(
                          context,
                          'Offline and maintenance piles',
                          items,
                          piles
                              .where(
                                (pile) =>
                                    pile.status == PileStatus.offline ||
                                    pile.status == PileStatus.maintenance,
                              )
                              .toList(),
                        ),
                  ),
                  _MetricCard(
                    label: 'Stations',
                    value: '${items.length}',
                    icon: Icons.location_city_outlined,
                    onTap: () => _showStationList(context, items),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Administration tools',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              _AdminTools(
                onStationSearch:
                    (value) => setState(() => stationQuery = value),
                actions: [
                  _AdminTool(
                    label: 'Users and roles',
                    icon: Icons.manage_accounts_outlined,
                    onPressed: () => context.push('/admin/users'),
                  ),
                  _AdminTool(
                    label: 'Revenue',
                    icon: Icons.payments_outlined,
                    onPressed: () => context.push('/admin/revenue'),
                  ),
                  _AdminTool(
                    label: 'Analytics',
                    icon: Icons.insights_outlined,
                    onPressed: () => context.push('/admin/analytics'),
                  ),
                  _AdminTool(
                    label: 'Tickets',
                    icon: Icons.build_circle_outlined,
                    onPressed: () => context.push('/admin/tickets'),
                  ),
                  _AdminTool(
                    label: 'Hazard reports',
                    icon: Icons.report_problem_outlined,
                    onPressed: () => context.push('/admin/reports'),
                  ),
                  _AdminTool(
                    label: 'Activity',
                    icon: Icons.history_outlined,
                    onPressed: () => context.push('/admin/activity'),
                  ),
                  _AdminTool(
                    label: 'Ratings',
                    icon: Icons.star_outline_rounded,
                    onPressed: () => context.push('/admin/ratings'),
                  ),
                  _AdminTool(
                    label: 'Vouchers',
                    icon: Icons.confirmation_number_outlined,
                    onPressed: () => context.push('/admin/vouchers'),
                  ),
                  _AdminTool(
                    label: 'Rewards',
                    icon: Icons.card_giftcard_outlined,
                    onPressed: () => context.push('/admin/rewards'),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              SectionTitle(
                title: 'Live pile telemetry',
                action: TextButton.icon(
                  onPressed: () => context.push('/admin/import'),
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Import'),
                ),
              ),
              const Text(
                'Changes are saved to Supabase and update the map live.',
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () => _showAddStation(context),
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('Add a new station'),
              ),
              const SizedBox(height: 14),
              if (widget.focusStationId != null)
                Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: ListTile(
                    leading: const Icon(Icons.flag_outlined),
                    title: const Text('Reported pile selected'),
                    subtitle: const Text(
                      'Update the highlighted pile below, then return to the hazard report.',
                    ),
                  ),
                ),
              if (stationItems.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('No stations match your search.'),
                ),
              for (final station in stationItems) ...[
                InkWell(
                  onTap: () => _showStationDetails(context, station),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            station.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Add pile',
                          onPressed: () => _showAddPile(context, station),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                        IconButton(
                          tooltip: 'Edit station',
                          onPressed: () => _showEditStation(context, station),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'Delete station',
                          onPressed:
                              () => _deleteStation(context, ref, station),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                for (final pile in station.piles)
                  Card(
                    color:
                        widget.focusPileId == pile.id
                            ? Theme.of(context).colorScheme.primaryContainer
                            : null,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${pile.label} · ${pile.connectorType} · ${pile.powerKw.toStringAsFixed(0)} kW',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text('RM ${pile.pricePerKwh.toStringAsFixed(2)}/kWh'),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: DropdownButton<PileStatus>(
                                    value:
                                        pile.status == PileStatus.reserved
                                            ? PileStatus.occupied
                                            : pile.status,
                                    underline: const SizedBox(),
                                    items:
                                        PileStatus.values
                                            .where(
                                              (status) =>
                                                  status != PileStatus.reserved,
                                            )
                                            .map(
                                              (status) => DropdownMenuItem(
                                                value: status,
                                                child: StatusPill(
                                                  status: status,
                                                ),
                                              ),
                                            )
                                            .toList(),
                                    onChanged: (status) async {
                                      if (status == null) return;
                                      try {
                                        await ref
                                            .read(stationRepositoryProvider)
                                            .updatePileStatus(
                                              stationId: station.id,
                                              pileId: pile.id,
                                              status: status,
                                            );
                                      } catch (error) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                friendlyErrorMessage(error),
                                              ),
                                            ),
                                          );
                                        }
                                      }
                                    },
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Edit pile',
                                onPressed:
                                    () => _showEditPile(context, station, pile),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: 'Delete pile',
                                onPressed:
                                    () => _deletePile(
                                      context,
                                      ref,
                                      station,
                                      pile,
                                    ),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
              ],
            ],
          );
        },
      ),
    );
  }

  void _showAddStation(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _AddStationSheet(),
    );
  }

  void _showEditStation(BuildContext context, ChargingStation station) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddStationSheet(station: station),
    );
  }

  Future<void> _deleteStation(
    BuildContext context,
    WidgetRef ref,
    ChargingStation station,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Remove station?'),
            content: Text(
              '${station.name} will be unpublished from the user map. Existing charging history will remain available.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Remove'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(stationRepositoryProvider).deleteStation(station.id);
      ref.invalidate(stationsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Station removed from the user map.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
      }
    }
  }

  void _showAddPile(BuildContext context, ChargingStation station) {
    showDialog<void>(
      context: context,
      builder: (_) => _PileEditorDialog(station: station),
    );
  }

  void _showEditPile(
    BuildContext context,
    ChargingStation station,
    ChargingPile pile,
  ) {
    showDialog<void>(
      context: context,
      builder: (_) => _PileEditorDialog(station: station, pile: pile),
    );
  }

  Future<void> _deletePile(
    BuildContext context,
    WidgetRef ref,
    ChargingStation station,
    ChargingPile pile,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Remove charging pile?'),
            content: Text(
              '${pile.label} will be removed from ${station.name}. Existing charging history will remain available.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Remove'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(stationRepositoryProvider).deletePile(pile.id);
      ref.invalidate(stationsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Charging pile removed.')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
      }
    }
  }

  void _showStationDetails(BuildContext context, ChargingStation station) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder:
          (_) => SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .82,
              ),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  Text(
                    station.name,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(station.address),
                  const SizedBox(height: 4),
                  Text(
                    '${station.brand} · ${station.indoorOutdoor} · ${station.localAuthority}',
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Coordinates: ${station.location.latitude.toStringAsFixed(6)}, '
                    '${station.location.longitude.toStringAsFixed(6)}',
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${station.availableCount} available · ${station.activeCount} active · '
                    '${station.piles.length} total piles',
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Charging piles (${station.piles.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  for (final pile in station.piles)
                    Card(
                      child: ListTile(
                        title: Text('${pile.label} · ${pile.connectorType}'),
                        subtitle: Text(
                          '${pile.powerKw.toStringAsFixed(0)} kW · RM ${pile.pricePerKwh.toStringAsFixed(2)}/kWh',
                        ),
                        trailing: StatusPill(status: pile.status),
                      ),
                    ),
                ],
              ),
            ),
          ),
    );
  }

  void _showPileStatusDetails(
    BuildContext context,
    String title,
    List<ChargingStation> stations,
    List<ChargingPile> piles,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder:
          (_) => _PileStatusSearchSheet(
            title: title,
            stations: stations,
            piles: piles,
          ),
    );
  }

  void _showStationList(BuildContext context, List<ChargingStation> stations) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder:
          (_) => _StationSearchSheet(
            stations: stations,
            onSelect: (station) {
              Navigator.of(context).pop();
              _showStationDetails(context, station);
            },
          ),
    );
  }
}

class _AdminTool {
  const _AdminTool({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
}

class _AdminTools extends StatefulWidget {
  const _AdminTools({required this.actions, required this.onStationSearch});

  final List<_AdminTool> actions;
  final ValueChanged<String> onStationSearch;

  @override
  State<_AdminTools> createState() => _AdminToolsState();
}

class _AdminToolsState extends State<_AdminTools> {
  final search = TextEditingController();
  bool searchOpen = false;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final action in widget.actions)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    avatar: Icon(action.icon, size: 18),
                    label: Text(action.label),
                    onPressed: action.onPressed,
                  ),
                ),
              IconButton(
                tooltip:
                    searchOpen ? 'Close station search' : 'Search stations',
                onPressed: () {
                  setState(() {
                    searchOpen = !searchOpen;
                    if (!searchOpen) {
                      search.clear();
                      widget.onStationSearch('');
                    }
                  });
                },
                icon: Icon(searchOpen ? Icons.close : Icons.search),
              ),
            ],
          ),
        ),
        if (searchOpen) ...[
          const SizedBox(height: 4),
          TextField(
            controller: search,
            autofocus: true,
            onChanged: widget.onStationSearch,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search stations',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ],
    );
  }
}

class _PileStatusSearchSheet extends StatefulWidget {
  const _PileStatusSearchSheet({
    required this.title,
    required this.stations,
    required this.piles,
  });

  final String title;
  final List<ChargingStation> stations;
  final List<ChargingPile> piles;

  @override
  State<_PileStatusSearchSheet> createState() => _PileStatusSearchSheetState();
}

class _PileStatusSearchSheetState extends State<_PileStatusSearchSheet> {
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stationById = {
      for (final station in widget.stations) station.id: station,
    };
    final query = search.text.trim().toLowerCase();
    final piles =
        widget.piles.where((pile) {
          if (query.isEmpty) return true;
          final station = stationById[pile.stationId];
          return pile.label.toLowerCase().contains(query) ||
              pile.connectorType.toLowerCase().contains(query) ||
              (station?.name.toLowerCase().contains(query) ?? false) ||
              (station?.address.toLowerCase().contains(query) ?? false);
        }).toList();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .82,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search station, bay, connector or address',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  if (piles.isEmpty) const Text('No matching piles.'),
                  for (final pile in piles)
                    Card(
                      child: ListTile(
                        title: Text(
                          '${stationById[pile.stationId]?.name ?? pile.stationId} · ${pile.label}',
                        ),
                        subtitle: Text(
                          '${stationById[pile.stationId]?.address ?? ''}\n'
                          '${pile.powerKw.toStringAsFixed(0)} kW · RM ${pile.pricePerKwh.toStringAsFixed(2)}/kWh',
                        ),
                        trailing: StatusPill(status: pile.status),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StationSearchSheet extends StatefulWidget {
  const _StationSearchSheet({required this.stations, required this.onSelect});

  final List<ChargingStation> stations;
  final ValueChanged<ChargingStation> onSelect;

  @override
  State<_StationSearchSheet> createState() => _StationSearchSheetState();
}

class _StationSearchSheetState extends State<_StationSearchSheet> {
  final search = TextEditingController();

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = search.text.trim().toLowerCase();
    final stations =
        widget.stations.where((station) {
          if (query.isEmpty) return true;
          return station.name.toLowerCase().contains(query) ||
              station.address.toLowerCase().contains(query) ||
              station.brand.toLowerCase().contains(query) ||
              station.localAuthority.toLowerCase().contains(query);
        }).toList();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .82,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Stations',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search station, address or brand',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  if (stations.isEmpty) const Text('No matching stations.'),
                  for (final station in stations)
                    Card(
                      child: ListTile(
                        title: Text(station.name),
                        subtitle: Text(
                          '${station.piles.length} pile(s) · ${station.address}',
                        ),
                        onTap: () {
                          widget.onSelect(station);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddStationSheet extends ConsumerStatefulWidget {
  const _AddStationSheet({this.station});

  final ChargingStation? station;

  @override
  ConsumerState<_AddStationSheet> createState() => _AddStationSheetState();
}

class _AddStationSheetState extends ConsumerState<_AddStationSheet> {
  final name = TextEditingController();
  final address = TextEditingController();
  final latitude = TextEditingController();
  final longitude = TextEditingController();
  final brand = TextEditingController(text: 'ChargeMY Prototype');
  final authority = TextEditingController();
  final power = TextEditingController(text: '60');
  final price = TextEditingController(text: '1.20');
  static const brandOptions = [
    'ChargeSini',
    'Gentari',
    'ParkEasy',
    'JomCharge',
    'EV Connection',
    'Tenaga Nasional',
    'ChargeMY Prototype',
  ];
  Timer? addressDebounce;
  List<Map<String, dynamic>> addressSuggestions = const [];
  bool suppressAddressListener = false;
  String connector = 'CCS2';
  String indoorOutdoor = 'Outdoor';
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final station = widget.station;
    if (station != null) {
      name.text = station.name;
      address.text = station.address;
      latitude.text = station.location.latitude.toStringAsFixed(6);
      longitude.text = station.location.longitude.toStringAsFixed(6);
      brand.text = station.brand;
      authority.text = station.localAuthority;
      final pile = station.piles.isEmpty ? null : station.piles.first;
      if (pile != null) {
        power.text = pile.powerKw.toStringAsFixed(1);
        price.text = pile.pricePerKwh.toStringAsFixed(2);
        connector = pile.connectorType;
      }
      indoorOutdoor = station.indoorOutdoor == 'Indoor' ? 'Indoor' : 'Outdoor';
    }
    address.addListener(_onAddressChanged);
  }

  @override
  void dispose() {
    addressDebounce?.cancel();
    address.removeListener(_onAddressChanged);
    name.dispose();
    address.dispose();
    latitude.dispose();
    longitude.dispose();
    brand.dispose();
    authority.dispose();
    power.dispose();
    price.dispose();
    super.dispose();
  }

  void _onAddressChanged() {
    if (!mounted || suppressAddressListener) return;
    final query = address.text.trim();
    addressDebounce?.cancel();
    if (query.length < 3) {
      setState(() => addressSuggestions = const []);
      return;
    }
    addressDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _searchAddress(query),
    );
  }

  Future<void> _searchAddress(String query) async {
    try {
      final response = await http.get(
        Uri.https('nominatim.openstreetmap.org', '/search', {
          'format': 'jsonv2',
          'q': query,
          'countrycodes': 'my',
          'limit': '5',
        }),
        headers: const {'User-Agent': 'ChargeMY/1.0 student prototype'},
      );
      if (response.statusCode != 200 || !mounted) return;
      final results =
          (jsonDecode(response.body) as List)
              .whereType<Map>()
              .map(
                (item) => <String, dynamic>{
                  'label': item['display_name'] as String? ?? query,
                  'lat': double.tryParse('${item['lat']}'),
                  'lng': double.tryParse('${item['lon']}'),
                },
              )
              .where((item) => item['lat'] != null && item['lng'] != null)
              .toList();
      if (mounted) setState(() => addressSuggestions = results);
    } catch (_) {
      if (mounted) setState(() => addressSuggestions = const []);
    }
  }

  void _selectAddress(Map<String, dynamic> result) {
    final lat = result['lat'] as double?;
    final lng = result['lng'] as double?;
    if (lat == null || lng == null) return;
    suppressAddressListener = true;
    address.text = result['label'] as String? ?? address.text;
    suppressAddressListener = false;
    latitude.text = lat.toStringAsFixed(6);
    longitude.text = lng.toStringAsFixed(6);
    setState(() => addressSuggestions = const []);
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final availableBrands = [
      ...brandOptions,
      if (brand.text.trim().isNotEmpty && !brandOptions.contains(brand.text))
        brand.text.trim(),
    ];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .88,
        ),
        child: Scrollbar(
          thumbVisibility: true,
          child: SingleChildScrollView(
            primary: true,
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.station == null
                      ? 'Add prototype station'
                      : 'Edit station',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.station == null
                      ? 'Creates one available simulated charging pile.'
                      : 'Update the station details shown to users. Pile settings are managed separately.',
                ),
                const SizedBox(height: 16),
                _field(name, 'Station name'),
                _field(address, 'Address'),
                if (addressSuggestions.isNotEmpty)
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (final result in addressSuggestions)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.location_on_outlined),
                            title: Text(
                              result['label'] as String,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _selectAddress(result),
                          ),
                      ],
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Search and select an address to set its map location.',
                  ),
                ),
                DropdownButtonFormField<String>(
                  value:
                      brand.text.trim().isEmpty
                          ? brandOptions.last
                          : brand.text.trim(),
                  decoration: const InputDecoration(
                    labelText: 'Charging brand',
                    border: OutlineInputBorder(),
                  ),
                  items:
                      availableBrands
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => brand.text = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                _field(authority, 'Local authority (e.g. DBKL / MBPJ)'),
                if (widget.station == null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: connector,
                          decoration: const InputDecoration(
                            labelText: 'Connector',
                            border: OutlineInputBorder(),
                          ),
                          items:
                              const ['CCS2', 'Type 2', 'CHAdeMO']
                                  .map(
                                    (value) => DropdownMenuItem(
                                      value: value,
                                      child: Text(value),
                                    ),
                                  )
                                  .toList(),
                          onChanged:
                              (value) => setState(() => connector = value!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: _locationSelector()),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _field(power, 'Power (kW)', number: true),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _field(price, 'Price (RM/kWh)', number: true),
                      ),
                    ],
                  ),
                ] else
                  _locationSelector(),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: saving ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(
                      saving
                          ? 'Saving...'
                          : widget.station == null
                          ? 'Create station'
                          : 'Save changes',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool number = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      keyboardType:
          number
              ? const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              )
              : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  Widget _locationSelector() => DropdownButtonFormField<String>(
    value: indoorOutdoor,
    decoration: const InputDecoration(
      labelText: 'Location',
      border: OutlineInputBorder(),
    ),
    items:
        const ['Indoor', 'Outdoor']
            .map((value) => DropdownMenuItem(value: value, child: Text(value)))
            .toList(),
    onChanged: (value) => setState(() => indoorOutdoor = value!),
  );

  Future<void> _save() async {
    final parsedLatitude = double.tryParse(latitude.text.trim());
    final parsedLongitude = double.tryParse(longitude.text.trim());
    final parsedPower = double.tryParse(power.text.trim());
    final parsedPrice = double.tryParse(price.text.trim());
    final requiredText = [name.text, address.text, brand.text, authority.text];
    if (requiredText.any((value) => value.trim().isEmpty) ||
        parsedLatitude == null ||
        parsedLongitude == null ||
        (widget.station == null &&
            (parsedPower == null || parsedPrice == null)) ||
        parsedLatitude < 0.8 ||
        parsedLatitude > 7.5 ||
        parsedLongitude < 99 ||
        parsedLongitude > 120 ||
        (widget.station == null && (parsedPower! < 0 || parsedPrice! < 0))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter valid Malaysian GPS coordinates and non-negative power and price.',
          ),
        ),
      );
      return;
    }
    setState(() => saving = true);
    try {
      final repository = ref.read(stationRepositoryProvider);
      if (widget.station == null) {
        await repository.createStation(
          name: name.text,
          address: address.text,
          latitude: parsedLatitude,
          longitude: parsedLongitude,
          brand: brand.text,
          indoorOutdoor: indoorOutdoor,
          localAuthority: authority.text,
          connectorType: connector,
          powerKw: parsedPower!,
          pricePerKwh: parsedPrice!,
        );
      } else {
        await repository.updateStation(
          stationId: widget.station!.id,
          name: name.text,
          address: address.text,
          latitude: parsedLatitude,
          longitude: parsedLongitude,
          brand: brand.text,
          indoorOutdoor: indoorOutdoor,
          localAuthority: authority.text,
        );
      }
      if (mounted) {
        ref.invalidate(stationsProvider);
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Station saved successfully.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

class _PileEditorDialog extends ConsumerStatefulWidget {
  const _PileEditorDialog({required this.station, this.pile});

  final ChargingStation station;
  final ChargingPile? pile;

  @override
  ConsumerState<_PileEditorDialog> createState() => _PileEditorDialogState();
}

class _PileEditorDialogState extends ConsumerState<_PileEditorDialog> {
  late final TextEditingController label;
  late final TextEditingController power;
  late final TextEditingController price;
  late String connector;
  late PileStatus status;
  bool saving = false;

  bool get _editing => widget.pile != null;

  @override
  void initState() {
    super.initState();
    final pile = widget.pile;
    label = TextEditingController(
      text:
          pile?.label ??
          'Bay ${(widget.station.piles.length + 1).toString().padLeft(2, '0')}',
    );
    power = TextEditingController(
      text: pile?.powerKw.toStringAsFixed(0) ?? '22',
    );
    price = TextEditingController(
      text: pile?.pricePerKwh.toStringAsFixed(2) ?? '0.90',
    );
    connector = pile?.connectorType ?? 'Type 2';
    status =
        pile?.status == PileStatus.reserved
            ? PileStatus.occupied
            : pile?.status ?? PileStatus.available;
  }

  @override
  void dispose() {
    label.dispose();
    power.dispose();
    price.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label, {String? helper}) =>
      InputDecoration(
        labelText: label,
        helperText: helper,
        filled: true,
        fillColor: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: .35),
        border: const OutlineInputBorder(),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 13,
          vertical: 14,
        ),
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
    titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
    contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
    actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
    title: Row(
      children: [
        CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
          child: Icon(
            _editing ? Icons.edit_outlined : Icons.add_circle_outline,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text('${_editing ? 'Edit' : 'Add'} charging pile')),
      ],
    ),
    content: SingleChildScrollView(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: .55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.station.name,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _editing
                        ? 'Update this pile’s settings.'
                        : 'Add a new charging option for this station.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: label,
              textCapitalization: TextCapitalization.words,
              decoration: _decoration('Pile label', helper: 'Example: Bay 02'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: power,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _decoration('Power (kW)'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _decoration('Price (RM/kWh)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: connector,
              isExpanded: true,
              decoration: _decoration('Connector type'),
              items:
                  const ['CCS2', 'Type 2', 'CHAdeMO']
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
              onChanged: (value) => setState(() => connector = value!),
            ),
            if (!_editing) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<PileStatus>(
                value: status,
                isExpanded: true,
                decoration: _decoration('Initial status'),
                items:
                    PileStatus.values
                        .where((value) => value != PileStatus.reserved)
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(statusLabel(value)),
                          ),
                        )
                        .toList(),
                onChanged: (value) => setState(() => status = value!),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton.icon(
        onPressed: saving ? null : _save,
        icon: Icon(_editing ? Icons.save_outlined : Icons.add),
        label: Text(
          saving ? 'Saving...' : (_editing ? 'Save changes' : 'Add pile'),
        ),
      ),
    ],
  );

  Future<void> _save() async {
    final parsedPower = double.tryParse(power.text.trim());
    final parsedPrice = double.tryParse(price.text.trim());
    if (label.text.trim().isEmpty ||
        parsedPower == null ||
        parsedPrice == null ||
        parsedPower < 0 ||
        parsedPrice < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a label and non-negative kW and price values.'),
        ),
      );
      return;
    }
    setState(() => saving = true);
    try {
      final repository = ref.read(stationRepositoryProvider);
      if (_editing) {
        await repository.updatePile(
          pileId: widget.pile!.id,
          label: label.text,
          connectorType: connector,
          powerKw: parsedPower,
          pricePerKwh: parsedPrice,
        );
      } else {
        await repository.createPile(
          stationId: widget.station.id,
          label: label.text,
          connectorType: connector,
          powerKw: parsedPower,
          pricePerKwh: parsedPrice,
          status: status,
        );
      }
      if (mounted) {
        ref.invalidate(stationsProvider);
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _editing ? 'Charging pile updated.' : 'Charging pile added.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    this.onTap,
  });
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const Spacer(),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
            Text(label, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    ),
  );
}
