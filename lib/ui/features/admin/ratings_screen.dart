import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/widgets.dart';

class RatingsScreen extends ConsumerStatefulWidget {
  const RatingsScreen({super.key});

  @override
  ConsumerState<RatingsScreen> createState() => _RatingsScreenState();
}

class _RatingsScreenState extends ConsumerState<RatingsScreen> {
  late Future<List<Map<String, dynamic>>> _ratings;

  @override
  void initState() {
    super.initState();
    _ratings = _load();
  }

  Future<List<Map<String, dynamic>>> _load() =>
      ref.read(stationRepositoryProvider).loadStationRatings();

  void _reload() => setState(() {
    _ratings = _load();
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Station ratings'),
      actions: [
        IconButton(
          tooltip: 'Refresh ratings',
          onPressed: _reload,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _ratings,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return AppStateMessage(
            icon: Icons.star_outline_rounded,
            title: 'Could not load ratings',
            message: friendlyErrorMessage(snapshot.error),
            actionLabel: 'Try again',
            onAction: _reload,
          );
        }
        final ratings = snapshot.data ?? const <Map<String, dynamic>>[];
        if (ratings.isEmpty) {
          return const AppStateMessage(
            icon: Icons.star_outline_rounded,
            title: 'No ratings yet',
            message: 'User station ratings and comments will appear here.',
          );
        }
        final summaries = _summaries(ratings)
          ..sort((a, b) => b.average.compareTo(a.average));
        final highest = summaries.first;
        final lowest = summaries.last;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Station performance',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _RatingHighlight(
                    label: 'Highest rated',
                    summary: highest,
                    icon: Icons.workspace_premium_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _RatingHighlight(
                    label: 'Lowest rated',
                    summary: lowest,
                    icon: Icons.trending_down_outlined,
                    warning: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Station feedback',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Select a station to view its ratings and comments.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            for (final summary in summaries)
              _StationRatingTile(
                summary: summary,
                onTap:
                    () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder:
                            (_) => _StationRatingDetailsScreen(
                              summary: summary,
                              ratings:
                                  ratings
                                      .where(
                                        (rating) =>
                                            '${rating['station_id']}' ==
                                            summary.stationId,
                                      )
                                      .toList(),
                            ),
                      ),
                    ),
              ),
          ],
        );
      },
    ),
  );

  List<_StationRatingSummary> _summaries(List<Map<String, dynamic>> ratings) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final rating in ratings) {
      grouped.putIfAbsent('${rating['station_id']}', () => []).add(rating);
    }
    return grouped.entries.map((entry) {
      final rows = entry.value;
      final total = rows.fold<double>(
        0,
        (sum, row) => sum + ((row['rating'] as num?)?.toDouble() ?? 0),
      );
      return _StationRatingSummary(
        stationId: entry.key,
        name: '${rows.first['station_name']}',
        average: total / rows.length,
        count: rows.length,
      );
    }).toList();
  }
}

class _StationRatingSummary {
  const _StationRatingSummary({
    required this.stationId,
    required this.name,
    required this.average,
    required this.count,
  });

  final String stationId;
  final String name;
  final double average;
  final int count;
}

class _RatingHighlight extends StatelessWidget {
  const _RatingHighlight({
    required this.label,
    required this.summary,
    required this.icon,
    this.warning = false,
  });

  final String label;
  final _StationRatingSummary summary;
  final IconData icon;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final color =
        warning
            ? const Color(0xFFB87500)
            : Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 14),
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 3),
            Text(
              summary.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 7),
            _StarValue(summary: summary, color: color),
          ],
        ),
      ),
    );
  }
}

class _StationRatingTile extends StatelessWidget {
  const _StationRatingTile({required this.summary, required this.onTap});

  final _StationRatingSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
        child: Icon(
          Icons.ev_station_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      title: Text(summary.name),
      subtitle: _StarValue(
        summary: summary,
        color: Theme.of(context).colorScheme.primary,
      ),
      trailing: const Icon(Icons.chevron_right),
    ),
  );
}

class _StarValue extends StatelessWidget {
  const _StarValue({required this.summary, required this.color});

  final _StationRatingSummary summary;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.star_rounded, size: 18, color: color),
      const SizedBox(width: 3),
      Text(
        summary.average.toStringAsFixed(2),
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
      const SizedBox(width: 4),
      Text(
        '${summary.count} rating${summary.count == 1 ? '' : 's'}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}

class _StationRatingDetailsScreen extends StatelessWidget {
  const _StationRatingDetailsScreen({
    required this.summary,
    required this.ratings,
  });

  final _StationRatingSummary summary;
  final List<Map<String, dynamic>> ratings;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(summary.name)),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rating overview',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                _StarValue(
                  summary: summary,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('User feedback', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        for (final rating in ratings) _RatingCard(rating: rating),
      ],
    ),
  );
}

class _RatingCard extends StatelessWidget {
  const _RatingCard({required this.rating});

  final Map<String, dynamic> rating;

  @override
  Widget build(BuildContext context) {
    final stars = (rating['rating'] as num?)?.toInt() ?? 0;
    final comment = '${rating['comment'] ?? ''}'.trim();
    final reviewerName = '${rating['reviewer_name'] ?? 'ChargeMY user'}';
    final avatarUrl = '${rating['reviewer_avatar_url'] ?? ''}'.trim();
    final date = DateTime.tryParse('${rating['updated_at']}')?.toLocal();
    final dateText =
        date == null
            ? 'Recently'
            : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  foregroundImage:
                      avatarUrl.isEmpty ? null : NetworkImage(avatarUrl),
                  child: Text(_initials(reviewerName)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reviewerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.star_rounded,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '$stars/5',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Text(dateText, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              comment.isEmpty ? 'No written feedback was provided.' : comment,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String value) {
    final words =
        value
            .trim()
            .split(RegExp(r'\s+'))
            .where((word) => word.isNotEmpty)
            .toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) return words.first.substring(0, 1).toUpperCase();
    return '${words.first[0]}${words.last[0]}'.toUpperCase();
  }
}
