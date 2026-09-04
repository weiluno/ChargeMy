import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app_dependencies.dart';
import '../../data/repositories/station_repository.dart';
import '../../domain/models/charging_models.dart';
import '../../services/local_notification_service.dart';

final dependenciesProvider = Provider<AppDependencies>(
  (ref) => AppDependencies(),
);

final stationRepositoryProvider = Provider<StationRepository>((ref) {
  return ref.watch(dependenciesProvider).stationRepository;
});

final stationsProvider = StreamProvider<List<ChargingStation>>((ref) {
  ref.watch(sessionProvider.select((session) => session.email));
  return ref.watch(stationRepositoryProvider).watchStations();
});

final hazardReportsProvider = StreamProvider<List<HazardReport>>((ref) {
  return ref.watch(stationRepositoryProvider).watchHazardReports();
});

final sessionProvider = ChangeNotifierProvider<SessionController>((ref) {
  return SessionController(client: Supabase.instance.client);
});

class SessionController extends ChangeNotifier {
  SessionController({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client {
    _authSubscription = _client.auth.onAuthStateChange.listen(
      (event) => _syncSupabaseUser(event.session?.user),
    );
    _syncSupabaseUser(_client.auth.currentUser);
  }

  final SupabaseClient _client;
  StreamSubscription<AuthState>? _authSubscription;
  UserRole _role = UserRole.guest;
  String _displayName = '';
  String? _avatarUrl;
  bool _hasPassword = false;
  VehicleProfile _vehicle = const VehicleProfile(
    id: 'proton-e-mas-5-standard',
    make: 'Proton',
    model: 'e.MAS 5 Standard',
    batteryKwh: 30.12,
    efficiencyWhPerKm: 133.8666667,
    connectorTypes: {'CCS2', 'Type 2'},
  );
  ChargingSession? _activeSession;
  int? _lastCompletedSoc;
  GeoLocation? _home;
  GeoLocation? _work;
  Timer? _chargeTimer;
  bool _chargeTickInFlight = false;
  String? _targetNotificationSessionId;

  UserRole get role => _role;
  String get displayName => _displayName;
  String? get avatarUrl => _avatarUrl;
  bool get hasPassword => _hasPassword;
  VehicleProfile get vehicle => _vehicle;
  ChargingSession? get activeSession => _activeSession;
  int? get lastCompletedSoc => _lastCompletedSoc;
  GeoLocation? get home => _home;
  GeoLocation? get work => _work;
  bool get isAuthenticated => _client.auth.currentSession != null;
  bool get isAdmin => _role == UserRole.admin;
  String? get email => _client.auth.currentUser?.email;
  bool get emailConfirmed => _client.auth.currentUser?.emailConfirmedAt != null;

  Future<void> signOut() async {
    await _client.auth.signOut();
    _role = UserRole.guest;
    _displayName = '';
    _avatarUrl = null;
    _hasPassword = false;
    clearActiveSession(notify: false);
    notifyListeners();
  }

  Future<void> signInWithEmail(String email, String password) async {
    await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    await refreshRole();
  }

  Future<void> registerWithEmail(
    String email,
    String password, {
    required String displayName,
  }) async {
    final response = await _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'display_name': displayName.trim()},
    );
    final user = response.user;
    final identities = user?.identities;
    if (user != null && identities != null && identities.isEmpty) {
      throw const AuthException(
        'An account already exists for this email. Try signing in.',
      );
    }
    if (user == null) {
      throw const AuthException(
        'The account could not be created. Please try again.',
      );
    }
    if (response.session != null) {
      await _client
          .from('profiles')
          .update({
            'display_name': displayName.trim(),
            'password_set': true,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', user.id);
    }
    await refreshRole();
  }

  Future<void> sendEmailOtp(String email, {bool shouldCreateUser = true}) =>
      _client.auth.signInWithOtp(
        email: email.trim(),
        shouldCreateUser: shouldCreateUser,
      );

  Future<void> verifyEmailOtp(String email, String token) async {
    await _client.auth.verifyOTP(
      email: email.trim(),
      token: token.trim(),
      type: OtpType.email,
    );
    await refreshRole();
  }

  Future<void> updateDisplayName(String name) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Sign in to edit your profile.');
    final value = name.trim();
    if (value.isEmpty) throw ArgumentError('Display name cannot be empty.');
    await _client
        .from('profiles')
        .update({
          'display_name': value,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', user.id);
    await _client.auth.updateUser(
      UserAttributes(data: {'display_name': value}),
    );
    _displayName = value;
    notifyListeners();
  }

  Future<void> setPassword(String password) async {
    final value = password.trim();
    if (value.length < 6) throw ArgumentError('Use at least 6 characters.');
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Sign in to set a password.');
    await _client.auth.updateUser(UserAttributes(password: value));
    await _client
        .from('profiles')
        .update({
          'password_set': true,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', user.id);
    _hasPassword = true;
    notifyListeners();
  }

  Future<void> uploadAvatar(Uint8List bytes, String fileName) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Sign in to upload a profile photo.');
    final extension = fileName.split('.').last.toLowerCase();
    final safeExtension =
        ['jpg', 'jpeg', 'png', 'webp'].contains(extension) ? extension : 'jpg';
    final path =
        '${user.id}/avatar-${DateTime.now().toUtc().millisecondsSinceEpoch}.$safeExtension';
    await _client.storage
        .from('avatars')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: safeExtension == 'png' ? 'image/png' : 'image/jpeg',
          ),
        );
    final url = _client.storage.from('avatars').getPublicUrl(path);
    await _client
        .from('profiles')
        .update({
          'avatar_url': url,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', user.id);
    _avatarUrl = url;
    notifyListeners();
  }

  Future<void> saveVehicle(VehicleProfile vehicle) async {
    _vehicle = vehicle;
    notifyListeners();
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client.from('vehicles').upsert({
      'user_id': user.id,
      'id': vehicle.id,
      'make': vehicle.make,
      'model': vehicle.model,
      'battery_kwh': vehicle.batteryKwh,
      'efficiency_wh_per_km': vehicle.efficiencyWhPerKm,
      'connector_types': vehicle.connectorTypes.toList(),
      'target_soc': vehicle.targetSoc,
      'reserve_soc': vehicle.reserveSoc,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    await _client
        .from('profiles')
        .update({
          'active_vehicle_id': vehicle.id,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', user.id);
  }

  Future<void> savePlace({
    required bool isHome,
    required GeoLocation location,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Sign in to save a location.');
    if (location.latitude.abs() > 90 || location.longitude.abs() > 180) {
      throw ArgumentError('Enter valid latitude and longitude values.');
    }
    await _client
        .from('profiles')
        .update({
          if (isHome) ...{
            'home_lat': location.latitude,
            'home_lng': location.longitude,
            'home_address': location.address,
          } else ...{
            'work_lat': location.latitude,
            'work_lng': location.longitude,
            'work_address': location.address,
          },
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', user.id);
    if (isHome) {
      _home = location;
    } else {
      _work = location;
    }
    notifyListeners();
  }

  void setActiveSession(ChargingSession session) {
    _activeSession = session;
    _startChargeMonitor();
    if (session.isCharging &&
        (session.stateOfCharge ?? session.startSoc ?? 0) <
            session.effectiveTargetSoc) {
      unawaited(_publishChargingNotification(session));
    }
    notifyListeners();
  }

  void clearActiveSession({bool notify = true}) {
    final active = _activeSession;
    if (active != null) {
      _lastCompletedSoc =
          (active.stateOfCharge ?? active.startSoc)?.clamp(0, 100).toInt();
    }
    _activeSession = null;
    _targetNotificationSessionId = null;
    _chargeTimer?.cancel();
    _chargeTimer = null;
    unawaited(LocalNotificationService.instance.clearChargingProgress());
    if (notify) notifyListeners();
  }

  void notifyTargetReached(int targetSoc) {
    final active = _activeSession;
    if (active == null || _targetNotificationSessionId == active.id) return;
    _targetNotificationSessionId = active.id;
    unawaited(
      LocalNotificationService.instance.showTargetReached(targetSoc: targetSoc),
    );
  }

  Future<void> _publishChargingNotification(ChargingSession session) {
    final current = session.stateOfCharge ?? session.startSoc ?? 0;
    return LocalNotificationService.instance.showChargingProgress(
      currentSoc: current,
      targetSoc: session.effectiveTargetSoc,
      remaining: session.estimatedRemaining,
    );
  }

  Future<void> refreshRole() => _syncSupabaseUser(_client.auth.currentUser);

  Future<void> _syncSupabaseUser(User? user) async {
    if (user == null) {
      _role = UserRole.guest;
      clearActiveSession(notify: false);
      notifyListeners();
      return;
    }
    Map<String, dynamic>? profile;
    try {
      final row =
          await _client
              .from('profiles')
              .select(
                'role, display_name, avatar_url, password_set, active_vehicle_id, home_lat, home_lng, home_address, work_lat, work_lng, work_address',
              )
              .eq('id', user.id)
              .maybeSingle();
      profile = row == null ? null : (row as Map).cast<String, dynamic>();
      final role = (profile?['role'] as String?)?.trim().toLowerCase();
      _role = role == 'admin' ? UserRole.admin : UserRole.user;
      _displayName = profile?['display_name'] as String? ?? '';
      _avatarUrl = profile?['avatar_url'] as String?;
      _hasPassword = profile?['password_set'] as bool? ?? false;
      _home = _locationFrom(profile, 'home_lat', 'home_lng', 'home_address');
      _work = _locationFrom(profile, 'work_lat', 'work_lng', 'work_address');
    } catch (_) {
      try {
        final roleRow =
            await _client
                .from('profiles')
                .select('role')
                .eq('id', user.id)
                .maybeSingle();
        final role = (roleRow?['role'] as String?)?.trim().toLowerCase();
        _role = role == 'admin' ? UserRole.admin : UserRole.user;
      } catch (_) {
        _role = UserRole.user;
      }
    }

    try {
      await _loadVehicle(user.id, profile?['active_vehicle_id'] as String?);
    } catch (_) {}

    try {
      final active =
          await _client
              .from('charging_sessions')
              .select()
              .eq('user_id', user.id)
              .eq('state', 'occupied')
              .order('started_at', ascending: false)
              .limit(1)
              .maybeSingle();
      _activeSession =
          active == null
              ? null
              : _sessionFromRow((active as Map).cast<String, dynamic>());
      if (_activeSession != null) {
        await _hydrateActiveSession();
        _startChargeMonitor();
      }
    } catch (_) {
      _activeSession = null;
    }
    notifyListeners();
  }

  Future<void> _loadVehicle(String uid, String? activeVehicleId) async {
    if (activeVehicleId == null) return;
    final data =
        await _client
            .from('vehicles')
            .select()
            .eq('user_id', uid)
            .eq('id', activeVehicleId)
            .maybeSingle();
    if (data == null) return;
    if (data['make'] == 'BYD' && data['model'] == 'Atto 3') {
      await saveVehicle(_vehicle);
      return;
    }
    final connectors =
        (data['connector_types'] as List? ?? const [])
            .whereType<String>()
            .toSet();
    if (connectors.isEmpty) return;
    _vehicle = VehicleProfile(
      id: data['id'] as String,
      make: data['make'] as String? ?? 'Unknown',
      model: data['model'] as String? ?? 'EV',
      batteryKwh: _double(data['battery_kwh'], 60),
      efficiencyWhPerKm: _double(data['efficiency_wh_per_km'], 160),
      connectorTypes: connectors,
      targetSoc: (data['target_soc'] as num?)?.toInt() ?? 80,
      reserveSoc: (data['reserve_soc'] as num?)?.toInt() ?? 15,
    );
  }

  Future<void> _hydrateActiveSession() async {
    final active = _activeSession;
    if (active == null) return;
    try {
      final pile =
          await _client
              .from('piles')
              .select('power_kw')
              .eq('id', active.pileId)
              .maybeSingle();
      final pilePower = _doubleNullable(pile?['power_kw']);
      _activeSession = active.copyWith(
        stateOfCharge: active.stateOfCharge ?? active.startSoc ?? 0,
        startSoc: active.startSoc ?? active.stateOfCharge ?? 0,
        targetSoc: active.targetSoc ?? _vehicle.targetSoc,
        chargePowerKw: math.min(
          active.chargePowerKw ?? pilePower ?? _vehicle.maxChargePowerKw,
          _vehicle.maxChargePowerKw,
        ),
        batteryKwh: active.batteryKwh ?? _vehicle.batteryKwh,
        startedAt: active.startedAt ?? DateTime.now(),
      );
    } catch (_) {
      _activeSession = active.copyWith(
        stateOfCharge: active.stateOfCharge ?? active.startSoc ?? 0,
        startSoc: active.startSoc ?? active.stateOfCharge ?? 0,
        targetSoc: active.targetSoc ?? _vehicle.targetSoc,
        chargePowerKw: math.min(
          active.chargePowerKw ?? _vehicle.maxChargePowerKw,
          _vehicle.maxChargePowerKw,
        ),
        batteryKwh: active.batteryKwh ?? _vehicle.batteryKwh,
        startedAt: active.startedAt ?? DateTime.now(),
      );
    }
  }

  void _startChargeMonitor() {
    _chargeTimer?.cancel();
    final active = _activeSession;
    if (active == null || !active.isCharging) return;
    _chargeTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _tickChargeProgress(),
    );
    unawaited(_tickChargeProgress());
  }

  Future<void> _tickChargeProgress() async {
    final active = _activeSession;
    if (active == null || !active.isCharging) return;
    final startedAt = active.startedAt;
    final power = active.chargePowerKw;
    final battery = active.batteryKwh;
    final startSoc = active.startSoc;
    if (startedAt == null ||
        power == null ||
        battery == null ||
        startSoc == null) {
      return;
    }
    final target = active.effectiveTargetSoc;
    final soc = socAfterCharging(
      batteryKwh: battery,
      stationPowerKw: power,
      startSoc: startSoc,
      targetSoc: target,
      elapsed: DateTime.now().difference(startedAt),
    );
    final previous = active.stateOfCharge ?? startSoc;
    if (soc > previous || soc >= target) {
      _activeSession = active.copyWith(stateOfCharge: soc);
      if (soc < target) await _publishChargingNotification(_activeSession!);
      notifyListeners();
    }
    if (soc >= target) {
      notifyTargetReached(target);
      _chargeTimer?.cancel();
      _chargeTimer = null;
    }
    if (soc <= previous && soc < target) return;
    if (_chargeTickInFlight) return;
    _chargeTickInFlight = true;
    try {
      final response = await _client
          .rpc(
            'record_charge_progress',
            params: {
              'p_session_id': active.id,
              'p_soc': soc,
              'p_energy_kwh': battery * (soc - startSoc) / 100,
            },
          )
          .timeout(const Duration(seconds: 10));
      final updated = _sessionFromRow(
        (response as Map).cast<String, dynamic>(),
      );
      final current = _activeSession;
      if (current == null || current.id != active.id) return;
      final currentSoc = current.stateOfCharge ?? soc;
      final savedSoc = updated.stateOfCharge ?? soc;
      _activeSession = updated.copyWith(
        stateOfCharge: math.max(currentSoc, savedSoc),
        startSoc: updated.startSoc ?? current.startSoc,
        targetSoc: updated.targetSoc ?? current.targetSoc,
        chargePowerKw: current.chargePowerKw ?? updated.chargePowerKw,
        batteryKwh: updated.batteryKwh ?? current.batteryKwh,
        startedAt: updated.startedAt ?? current.startedAt,
      );
      notifyListeners();
    } catch (_) {
    } finally {
      _chargeTickInFlight = false;
    }
  }

  ChargingSession _sessionFromRow(Map<String, dynamic> data) => ChargingSession(
    id: data['id'] as String,
    stationId: data['station_id'] as String,
    pileId: data['pile_id'] as String,
    expiresAt:
        data['expires_at'] == null
            ? DateTime.now().add(const Duration(hours: 12))
            : DateTime.parse('${data['expires_at']}').toLocal(),
    isCharging: data['state'] == 'occupied',
    stateOfCharge: (data['end_soc'] as num?)?.toInt(),
    startSoc: (data['start_soc'] as num?)?.toInt(),
    targetSoc: (data['target_soc'] as num?)?.toInt(),
    chargePowerKw: _doubleNullable(data['charge_power_kw']),
    batteryKwh: _doubleNullable(data['battery_kwh']),
    startedAt:
        data['started_at'] == null
            ? null
            : DateTime.tryParse('${data['started_at']}')?.toLocal(),
  );

  double _double(Object? value, double fallback) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? fallback;

  double? _doubleNullable(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value');

  GeoLocation? _locationFrom(
    Map<String, dynamic>? profile,
    String latitudeKey,
    String longitudeKey,
    String addressKey,
  ) {
    if (profile == null) return null;
    final latitude = profile[latitudeKey];
    final longitude = profile[longitudeKey];
    if (latitude is! num || longitude is! num) return null;
    return GeoLocation(
      latitude.toDouble(),
      longitude.toDouble(),
      address: profile[addressKey] as String?,
    );
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _chargeTimer?.cancel();
    super.dispose();
  }
}
