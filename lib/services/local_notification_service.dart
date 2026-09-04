import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationService {
  LocalNotificationService._();

  static final instance = LocalNotificationService._();
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> initialize() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    _ready = true;
  }

  Future<void> showTargetReached({required int targetSoc}) async {
    try {
      await initialize();
      final androidDetails = AndroidNotificationDetails(
        'chargemy_charging_complete_v2',
        'Charging completed',
        channelDescription: 'ChargeMY completed charging alerts',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      );
      final details = NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      );
      await _plugin.show(
        1001,
        'Target charge reached',
        'Your vehicle reached $targetSoc%. Unplug within 10 minutes to avoid idle fees.',
        details,
        payload: 'charging-target-reached',
      );
      await _plugin.cancel(1002);
    } catch (_) {}
  }

  Future<void> showChargingProgress({
    required int currentSoc,
    required int targetSoc,
    Duration? remaining,
  }) async {
    try {
      await initialize();
      final androidDetails = AndroidNotificationDetails(
        'chargemy_charging',
        'Charging updates',
        channelDescription: 'ChargeMY charging progress and target alerts',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
        showProgress: true,
        maxProgress: 100,
        progress: currentSoc.clamp(0, 100).toInt(),
      );
      final details = NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(
          presentAlert: false,
          presentSound: false,
        ),
      );
      final eta =
          remaining == null ? '' : ' · ${remaining.inMinutes} min remaining';
      await _plugin.show(
        1002,
        'ChargeMY charging: $currentSoc% / $targetSoc%',
        'Charging in progress$eta',
        details,
      );
    } catch (_) {}
  }

  Future<void> clearChargingProgress() async {
    try {
      await initialize();
      await _plugin.cancel(1002);
    } catch (_) {}
  }
}
