import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/charging_models.dart';
import '../../core/app_state.dart';
import '../../core/widgets.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  late Future<List<AppNotification>> _notifications;

  @override
  void initState() {
    super.initState();
    _notifications = ref.read(stationRepositoryProvider).loadNotifications();
  }

  void _refresh() => setState(
    () =>
        _notifications =
            ref.read(stationRepositoryProvider).loadNotifications(),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Alerts'),
      actions: [
        IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
      ],
    ),
    body: FutureBuilder<List<AppNotification>>(
      future: _notifications,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Could not load alerts: ${friendlyErrorMessage(snapshot.error)}',
            ),
          );
        }
        final items = snapshot.data ?? const [];
        if (items.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Text(
                'No alerts yet. Favourite availability, charging target and nearby-station events will appear here.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                color:
                    item.isRead
                        ? null
                        : Theme.of(context).colorScheme.primaryContainer,
                child: ListTile(
                  leading: Icon(_icon(item.type)),
                  title: Text(item.title),
                  subtitle: Text('${item.body}\n${_when(item.createdAt)}'),
                  isThreeLine: true,
                  onTap:
                      item.isRead
                          ? null
                          : () async {
                            await ref
                                .read(stationRepositoryProvider)
                                .markNotificationRead(item.id);
                            _refresh();
                          },
                ),
              );
            },
          ),
        );
      },
    ),
  );

  IconData _icon(String type) => switch (type) {
    'favourite_available' => Icons.favorite,
    'idle_fee_warning' => Icons.timer_outlined,
    'nearby_new_station' => Icons.add_location_alt_outlined,
    'reservation_abandonment' => Icons.route_outlined,
    _ => Icons.notifications_outlined,
  };

  String _when(DateTime time) =>
      '${time.day.toString().padLeft(2, '0')}/${time.month.toString().padLeft(2, '0')} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}
