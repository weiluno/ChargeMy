import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/charging_models.dart';
import '../../core/app_state.dart';
import '../../core/widgets.dart';

class HazardReportsScreen extends ConsumerStatefulWidget {
  const HazardReportsScreen({super.key});

  @override
  ConsumerState<HazardReportsScreen> createState() =>
      _HazardReportsScreenState();
}

class _HazardReportsScreenState extends ConsumerState<HazardReportsScreen> {
  late Future<List<HazardReport>> _reports;
  final _search = TextEditingController();
  final _stationNames = <String, String>{};
  final _pileLabels = <String, String>{};
  String _statusFilter = 'all';
  bool _searchOpen = false;

  @override
  void initState() {
    super.initState();
    _reports = _loadReports();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<List<HazardReport>> _loadReports() async {
    final stations = await ref.read(stationsProvider.future);
    _stationNames
      ..clear()
      ..addEntries(
        stations.map((station) => MapEntry(station.id, station.name)),
      );
    _pileLabels
      ..clear()
      ..addEntries(
        stations.expand(
          (station) =>
              station.piles.map((pile) => MapEntry(pile.id, pile.label)),
        ),
      );
    return ref
        .read(stationRepositoryProvider)
        .loadHazardReports(stations.map((station) => station.id).toList());
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hazard reports'),
        actions: [
          IconButton(
            tooltip: _searchOpen ? 'Close report search' : 'Search reports',
            icon: Icon(_searchOpen ? Icons.close : Icons.search),
            onPressed:
                () => setState(() {
                  _searchOpen = !_searchOpen;
                  if (!_searchOpen) _search.clear();
                }),
          ),
          IconButton(
            tooltip: 'Refresh reports',
            icon: const Icon(Icons.refresh),
            onPressed:
                () => setState(() {
                  _reports = _loadReports();
                }),
          ),
        ],
      ),
      body:
          !session.isAdmin
              ? const Center(child: Text('Admin access is required.'))
              : FutureBuilder<List<HazardReport>>(
                future: _reports,
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
                                'Could not load hazard reports. Please try again.',
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  final query = _search.text.trim().toLowerCase();
                  final reports =
                      (snapshot.data ?? const []).where((report) {
                        if (_statusFilter != 'all' &&
                            report.status != _statusFilter) {
                          return false;
                        }
                        if (query.isEmpty) return true;
                        final station = _stationNames[report.stationId] ?? '';
                        final pile =
                            report.pileId == null
                                ? ''
                                : (_pileLabels[report.pileId!] ??
                                    report.pileId!);
                        return '$station ${report.category} ${report.note} $pile'
                            .toLowerCase()
                            .contains(query);
                      }).toList();
                  if (_searchOpen) {
                    return Column(
                      children: [
                        _filterBar(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                          child: TextField(
                            controller: _search,
                            autofocus: true,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              hintText: 'Search station, pile or hazard',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        Expanded(child: _reportList(context, reports)),
                      ],
                    );
                  }
                  if (reports.isEmpty) {
                    return Column(
                      children: [
                        _filterBar(),
                        const Expanded(
                          child: Center(
                            child: Text('No hazard reports match this filter.'),
                          ),
                        ),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      _filterBar(),
                      Expanded(child: _reportList(context, reports)),
                    ],
                  );
                },
              ),
    );
  }

  Widget _filterBar() => SizedBox(
    height: 48,
    child: ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      scrollDirection: Axis.horizontal,
      children: [
        for (final status in const ['all', 'ongoing', 'completed', 'cancelled'])
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(status == 'all' ? 'All' : _label(status)),
              selected: _statusFilter == status,
              onSelected: (_) => setState(() => _statusFilter = status),
            ),
          ),
      ],
    ),
  );

  Widget _reportList(BuildContext context, List<HazardReport> reports) {
    if (reports.isEmpty) {
      return const Center(child: Text('No hazard reports match this filter.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: reports.length,
      itemBuilder: (context, index) {
        final report = reports[index];
        final time =
            report.createdAt == null
                ? 'Just submitted'
                : '${report.createdAt!.day}/${report.createdAt!.month} ${TimeOfDay.fromDateTime(report.createdAt!).format(context)}';
        final station = _stationNames[report.stationId] ?? report.stationId;
        final pile =
            report.pileId == null
                ? 'Station-wide'
                : (_pileLabels[report.pileId!] ?? report.pileId!);
        return Card(
          child: ListTile(
            onTap: () => _showReportDetails(context, report),
            leading: const CircleAvatar(
              child: Icon(Icons.report_problem_outlined),
            ),
            title: Text(report.category),
            subtitle: Text('$station · $pile\n${report.note}\n$time'),
            trailing: _StatusPill(label: _label(report.status)),
            isThreeLine: true,
          ),
        );
      },
    );
  }

  String _label(String status) => switch (status) {
    'ongoing' => 'Ongoing',
    'completed' => 'Completed',
    'cancelled' => 'Cancelled',
    'submitted' => 'Submitted',
    _ => 'All',
  };

  Future<void> _showReportDetails(
    BuildContext context,
    HazardReport report,
  ) async {
    final evidencePaths =
        report.imagePaths.isNotEmpty
            ? report.imagePaths
            : report.imagePath == null
            ? const <String>[]
            : [report.imagePath!];
    var imageUrls = <String>[];
    if (evidencePaths.isNotEmpty) {
      try {
        imageUrls =
            (await Future.wait(
              evidencePaths.map(
                ref.read(stationRepositoryProvider).getHazardEvidenceUrl,
              ),
            )).whereType<String>().toList();
      } catch (_) {
        imageUrls = [];
      }
    }
    if (!context.mounted) return;
    final station = _stationNames[report.stationId] ?? report.stationId;
    final pile =
        report.pileId == null
            ? 'Station-wide'
            : (_pileLabels[report.pileId!] ?? report.pileId!);
    await showDialog<void>(
      context: context,
      builder:
          (dialogContext) => Dialog(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 420,
                maxHeight: MediaQuery.sizeOf(dialogContext).height * .82,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor:
                              Theme.of(
                                dialogContext,
                              ).colorScheme.errorContainer,
                          child: Icon(
                            Icons.report_problem_outlined,
                            color: Theme.of(dialogContext).colorScheme.error,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            station,
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
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color:
                            Theme.of(
                              dialogContext,
                            ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ReportInfoRow(
                            icon: Icons.warning_amber_outlined,
                            label: 'Hazard',
                            value: report.category,
                          ),
                          _ReportInfoRow(
                            icon: Icons.ev_station_outlined,
                            label: 'Pile',
                            value: pile,
                          ),
                          _ReportInfoRow(
                            icon: Icons.timelapse_outlined,
                            label: 'Status',
                            value: _label(report.status),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          dialogContext,
                        ).colorScheme.secondaryContainer.withValues(alpha: .45),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.format_quote_outlined,
                                size: 19,
                                color:
                                    Theme.of(dialogContext).colorScheme.primary,
                              ),
                              const SizedBox(width: 7),
                              Text(
                                'User’s description',
                                style:
                                    Theme.of(
                                      dialogContext,
                                    ).textTheme.titleSmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            report.note,
                            style: Theme.of(dialogContext).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    if (imageUrls.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        'Photo evidence',
                        style: Theme.of(dialogContext).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      _EvidenceGallery(imageUrls: imageUrls),
                    ] else if (evidencePaths.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          'Photo evidence is not currently available.',
                        ),
                      ),
                    const SizedBox(height: 20),
                    if (report.pileId != null)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          onPressed: () {
                            Navigator.of(dialogContext).pop();
                            final station = Uri.encodeComponent(
                              report.stationId,
                            );
                            final pile = Uri.encodeComponent(report.pileId!);
                            context.go('/admin?station=$station&pile=$pile');
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Select the reported pile to update its status.',
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.tune_outlined),
                          label: const Text('Set pile status'),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              await _setStatus(report, 'completed');
                              if (dialogContext.mounted) {
                                Navigator.of(dialogContext).pop();
                              }
                            },
                            child: const Text('Mark completed'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () async {
                            await _setStatus(report, 'cancelled');
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                          },
                          child: const Text('Cancel report'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  Future<void> _setStatus(HazardReport report, String status) async {
    try {
      await ref
          .read(stationRepositoryProvider)
          .updateHazardReportStatus(report.id, status);
      if (mounted) {
        setState(() {
          _reports = _loadReports();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Hazard report marked ${_label(status).toLowerCase()}.',
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
    }
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(label, style: Theme.of(context).textTheme.labelSmall),
  );
}

class _ReportInfoRow extends StatelessWidget {
  const _ReportInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 9),
        Text('$label: ', style: Theme.of(context).textTheme.labelMedium),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

class _EvidenceGallery extends StatefulWidget {
  const _EvidenceGallery({required this.imageUrls});

  final List<String> imageUrls;

  @override
  State<_EvidenceGallery> createState() => _EvidenceGalleryState();
}

class _EvidenceGalleryState extends State<_EvidenceGallery> {
  var _page = 0;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(
        height: 220,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: PageView.builder(
            itemCount: widget.imageUrls.length,
            onPageChanged: (page) => setState(() => _page = page),
            itemBuilder:
                (context, index) => Image.network(
                  widget.imageUrls[index],
                  fit: BoxFit.cover,
                  errorBuilder:
                      (_, _, _) => const Center(
                        child: Text('This photo is no longer available.'),
                      ),
                ),
          ),
        ),
      ),
      if (widget.imageUrls.length > 1) ...[
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var index = 0; index < widget.imageUrls.length; index += 1)
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: index == _page ? 18 : 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color:
                      index == _page
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '${_page + 1} of ${widget.imageUrls.length} · Swipe to view photos',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ],
  );
}
