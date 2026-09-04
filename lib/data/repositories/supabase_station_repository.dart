import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/charging_models.dart';
import 'station_repository.dart';

class SupabaseStationRepository implements StationRepository {
  SupabaseStationRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Stream<List<ChargingStation>> watchStations() {
    late StreamSubscription<List<Map<String, dynamic>>> stationSubscription;
    late StreamSubscription<List<Map<String, dynamic>>> pileSubscription;
    final controller = StreamController<List<ChargingStation>>();
    var stations = <Map<String, dynamic>>[];
    var piles = <Map<String, dynamic>>[];
    var readyStations = false;
    var readyPiles = false;

    Future<void> publish() async {
      if (!readyStations || !readyPiles || controller.isClosed) return;
      try {
        final favourites = await _favouriteIds();
        final byStation = <String, List<ChargingPile>>{};
        for (final row in piles) {
          final pile = _pile(row);
          byStation.putIfAbsent(pile.stationId, () => []).add(pile);
        }
        for (final stationPiles in byStation.values) {
          stationPiles.sort((left, right) {
            final order = _pileNumber(
              left.label,
            ).compareTo(_pileNumber(right.label));
            return order == 0 ? left.label.compareTo(right.label) : order;
          });
        }
        final result =
            stations
                .map(
                  (row) => ChargingStation(
                    id: row['id'] as String,
                    name: cleanDisplayText(
                      row['name'] as String?,
                      fallback: 'Unnamed station',
                    ),
                    address: cleanDisplayText(row['address'] as String?),
                    location: GeoLocation(
                      _double(row['latitude'], 3.139),
                      _double(row['longitude'], 101.6869),
                    ),
                    brand: cleanDisplayText(
                      row['brand'] as String?,
                      fallback: 'Unknown',
                    ),
                    indoorOutdoor: cleanDisplayText(
                      row['indoor_outdoor'] as String?,
                      fallback: 'Unknown',
                    ),
                    localAuthority: cleanDisplayText(
                      row['local_authority'] as String?,
                      fallback: 'Unknown',
                    ),
                    piles: byStation[row['id'] as String] ?? const [],
                    isFavourite: favourites.contains(row['id']),
                  ),
                )
                .toList();
        result.sort((left, right) {
          if (left.isFavourite != right.isFavourite) {
            return left.isFavourite ? -1 : 1;
          }
          return left.name.compareTo(right.name);
        });
        controller.add(result);
      } catch (error, stackTrace) {
        controller.addError(error, stackTrace);
      }
    }

    controller.onListen = () {
      stationSubscription = _client
          .from('stations')
          .stream(primaryKey: ['id'])
          .eq('is_published', true)
          .order('name')
          .listen((rows) {
            stations = rows;
            readyStations = true;
            publish();
          }, onError: controller.addError);
      pileSubscription = _client
          .from('piles')
          .stream(primaryKey: ['id'])
          .eq('is_active', true)
          .listen((rows) {
            piles = rows;
            readyPiles = true;
            publish();
          }, onError: controller.addError);
    };
    controller.onCancel = () async {
      await stationSubscription.cancel();
      await pileSubscription.cancel();
    };
    return controller.stream;
  }

  @override
  Stream<List<HazardReport>> watchHazardReports() => _client
      .from('hazard_reports')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .map((rows) => rows.map(_hazard).toList());

  @override
  Future<List<HazardReport>> loadHazardReports(List<String> stationIds) async {
    if (stationIds.isEmpty) return [];
    final rows = await _client
        .from('hazard_reports')
        .select()
        .inFilter('station_id', stationIds)
        .order('created_at', ascending: false);
    return (rows as List).cast<Map<String, dynamic>>().map(_hazard).toList();
  }

  @override
  Future<void> updateHazardReportStatus(String reportId, String status) async {
    if (!const [
      'submitted',
      'ongoing',
      'completed',
      'cancelled',
    ].contains(status)) {
      throw StateError('Choose a valid hazard report status.');
    }
    await _client
        .from('hazard_reports')
        .update({'status': status})
        .eq('id', reportId);
  }

  @override
  Future<String?> getHazardEvidenceUrl(String imagePath) async {
    return _client.storage.from('reports').createSignedUrl(imagePath, 3600);
  }

  @override
  Future<List<MaintenanceTicket>> loadTickets() async {
    final rows = await _client
        .from('tickets')
        .select()
        .order('opened_at', ascending: false);
    return (rows as List).cast<Map<String, dynamic>>().map(_ticket).toList();
  }

  @override
  Future<List<StationDailyAnalytics>> loadDailyAnalytics() async {
    final rows = await _client
        .from('station_daily_analytics')
        .select()
        .order('day', ascending: false);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(
          (row) => StationDailyAnalytics(
            stationId: row['station_id'] as String,
            day: DateTime.tryParse('${row['day']}') ?? DateTime.now(),
            completedSessions:
                (row['completed_sessions'] as num?)?.toInt() ?? 0,
            averageStayMinutes:
                (row['average_stay_minutes'] as num?)?.toDouble(),
          ),
        )
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> loadMaintenanceCandidates() async {
    final cutoff =
        DateTime.now()
            .toUtc()
            .subtract(const Duration(hours: 200))
            .toIso8601String();
    final sessions = await _client
        .from('charging_sessions')
        .select('id,station_id,pile_id,started_at,charge_power_kw')
        .eq('state', 'occupied')
        .lt('started_at', cutoff)
        .order('started_at');
    final rows = (sessions as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return const [];
    final pileIds = rows.map((row) => '${row['pile_id']}').toList();
    final piles = await _client
        .from('piles')
        .select('id,maintenance_alert_acknowledged_at')
        .inFilter('id', pileIds);
    final acknowledgedAt = <String, DateTime?>{
      for (final pile in (piles as List).cast<Map<String, dynamic>>())
        '${pile['id']}': DateTime.tryParse(
          '${pile['maintenance_alert_acknowledged_at'] ?? ''}',
        ),
    };
    return rows.where((row) {
      final startedAt = DateTime.tryParse('${row['started_at'] ?? ''}');
      final acknowledged = acknowledgedAt['${row['pile_id']}'];
      return acknowledged == null ||
          startedAt == null ||
          acknowledged.isBefore(startedAt);
    }).toList();
  }

  @override
  Future<void> markMaintenanceCandidateCompleted(String pileId) => _client
      .from('piles')
      .update({
        'maintenance_alert_acknowledged_at':
            DateTime.now().toUtc().toIso8601String(),
      })
      .eq('id', pileId);

  @override
  Future<List<ChargingPayment>> loadMyPayments() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const <ChargingPayment>[];
    final rows = await _client
        .from('charging_payments')
        .select(
          'id, session_id, station_id, energy_kwh, amount_myr, status, paid_at, receipt_email, stations(name)',
        )
        .eq('user_id', userId)
        .order('paid_at', ascending: false)
        .limit(100);
    return (rows as List).cast<Map<String, dynamic>>().map((row) {
      final station = row['stations'];
      final stationName =
          station is Map
              ? station['name'] as String? ?? row['station_id'] as String
              : row['station_id'] as String;
      return ChargingPayment(
        id: row['id'] as String,
        sessionId: row['session_id'] as String,
        stationId: row['station_id'] as String,
        stationName: cleanDisplayText(
          stationName,
          fallback: 'Charging station',
        ),
        energyKwh: _double(row['energy_kwh'], 0),
        amountMyr: _double(row['amount_myr'], 0),
        status: row['status'] as String? ?? 'paid',
        paidAt:
            DateTime.tryParse('${row['paid_at']}')?.toLocal() ?? DateTime.now(),
        receiptEmail: row['receipt_email'] as String?,
      );
    }).toList();
  }

  @override
  Future<List<Voucher>> loadMyVouchers() async {
    if (_client.auth.currentUser == null) return const <Voucher>[];
    final rows = await _client.rpc('my_vouchers');
    return (rows as List).cast<Map<String, dynamic>>().map((row) {
      return Voucher(
        claimId: '${row['claim_id']}',
        code: '${row['code']}',
        title: '${row['title']}',
        description: '${row['description'] ?? ''}',
        discountType: '${row['discount_type'] ?? 'fixed'}',
        discountValue: _double(row['discount_value'], 0),
        minimumSpendMyr: _double(row['minimum_spend_myr'], 0),
        claimedAt:
            DateTime.tryParse('${row['claimed_at']}')?.toLocal() ??
            DateTime.now(),
        expiresAt:
            row['expires_at'] == null
                ? null
                : DateTime.tryParse('${row['expires_at']}')?.toLocal(),
        usedAt:
            row['used_at'] == null
                ? null
                : DateTime.tryParse('${row['used_at']}')?.toLocal(),
        isActive: row['is_active'] == true,
        isRewardVoucher: row['is_reward_voucher'] == true,
      );
    }).toList();
  }

  @override
  Future<Voucher> claimVoucher(String code) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign in is required.');
    final voucher =
        await _client
            .from('vouchers')
            .select()
            .eq('code', code.trim().toUpperCase())
            .maybeSingle();
    if (voucher == null) {
      throw StateError('This voucher code is not available.');
    }
    final now = DateTime.now();
    final startsAt = DateTime.tryParse('${voucher['starts_at']}')?.toLocal();
    final expiresAt =
        voucher['expires_at'] == null
            ? null
            : DateTime.tryParse('${voucher['expires_at']}')?.toLocal();
    if (expiresAt != null && !expiresAt.isAfter(now)) {
      throw StateError('This voucher has expired and can no longer be used.');
    }
    if (voucher['is_active'] != true) {
      throw StateError('This voucher is currently paused and cannot be used.');
    }
    if (startsAt != null && startsAt.isAfter(now)) {
      throw StateError('This voucher is not available yet.');
    }
    final voucherId = '${voucher['id']}';
    final existing =
        await _client
            .from('voucher_claims')
            .select('id')
            .eq('voucher_id', voucherId)
            .eq('user_id', userId)
            .maybeSingle();
    if (existing != null) {
      throw StateError('You have already claimed this voucher.');
    }
    final claimId = _newVoucherId();
    final claimedAt = DateTime.now();
    await _client.from('voucher_claims').insert({
      'id': claimId,
      'voucher_id': voucherId,
      'user_id': userId,
    });
    return Voucher(
      claimId: claimId,
      code: '${voucher['code']}',
      title: '${voucher['title']}',
      description: '${voucher['description'] ?? ''}',
      discountType: '${voucher['discount_type'] ?? 'fixed'}',
      discountValue: _double(voucher['discount_value'], 0),
      minimumSpendMyr: _double(voucher['minimum_spend_myr'], 0),
      claimedAt: claimedAt,
      expiresAt: expiresAt,
      isActive: voucher['is_active'] == true,
    );
  }

  @override
  Future<RewardSummary> loadMyRewards() async {
    if (_client.auth.currentUser == null) {
      return const RewardSummary(pointsBalance: 0, rewards: [], history: []);
    }
    final results = await Future.wait<dynamic>([
      _client.rpc('my_reward_points'),
      _client
          .from('reward_catalog')
          .select()
          .eq('is_active', true)
          .order('points_required'),
      _client.rpc('my_reward_redemptions'),
    ]);
    final rewardRows = (results[1] as List).cast<Map<String, dynamic>>();
    final historyRows = (results[2] as List).cast<Map<String, dynamic>>();
    return RewardSummary(
      pointsBalance: (results[0] as num?)?.toInt() ?? 0,
      rewards:
          (rewardRows.map(_reward).toList()..sort(
            (left, right) =>
                left.pointsRequired.compareTo(right.pointsRequired),
          )),
      history:
          historyRows
              .map(
                (row) => RewardRedemption(
                  id: '${row['id']}',
                  rewardTitle: '${row['reward_title']}',
                  pointsSpent: (row['points_spent'] as num?)?.toInt() ?? 0,
                  discountMyr: _double(row['discount_myr'], 0),
                  voucherCode: '${row['voucher_code']}',
                  redeemedAt:
                      DateTime.tryParse('${row['redeemed_at']}')?.toLocal() ??
                      DateTime.now(),
                ),
              )
              .toList(),
    );
  }

  @override
  Future<RewardSummary> redeemReward(String rewardId) async {
    await _client.rpc('redeem_reward', params: {'p_reward_id': rewardId});
    return loadMyRewards();
  }

  @override
  Future<List<Map<String, dynamic>>> loadAdminRewards() async {
    final rows = await _client
        .from('reward_catalog')
        .select()
        .order('points_required');
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .where((row) => row['is_deleted'] != true)
        .toList();
  }

  @override
  Future<Map<String, dynamic>> createReward({
    required String title,
    required String description,
    required int pointsRequired,
    required double discountMyr,
    required double minimumSpendMyr,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final row = <String, dynamic>{
      'id': _newVoucherId(),
      'title': title.trim(),
      'description': description.trim(),
      'points_required': pointsRequired,
      'discount_myr': discountMyr,
      'minimum_spend_myr': max(minimumSpendMyr, discountMyr + 2),
      'is_active': true,
      'created_by': _client.auth.currentUser?.id,
      'created_at': now,
      'updated_at': now,
    };
    await _client.from('reward_catalog').insert(row);
    return row;
  }

  @override
  Future<Map<String, dynamic>> updateReward({
    required String rewardId,
    required String title,
    required String description,
    required int pointsRequired,
    required double discountMyr,
    required double minimumSpendMyr,
  }) async {
    final row = <String, dynamic>{
      'id': rewardId,
      'title': title.trim(),
      'description': description.trim(),
      'points_required': pointsRequired,
      'discount_myr': discountMyr,
      'minimum_spend_myr': max(minimumSpendMyr, discountMyr + 2),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _client.from('reward_catalog').update(row).eq('id', rewardId);
    return row;
  }

  @override
  Future<void> setRewardActive({
    required String rewardId,
    required bool isActive,
  }) => _client
      .from('reward_catalog')
      .update({
        'is_active': isActive,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      })
      .eq('id', rewardId);

  @override
  Future<void> deleteReward(String rewardId) => _client
      .from('reward_catalog')
      .update({
        'is_active': false,
        'is_deleted': true,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      })
      .eq('id', rewardId);

  @override
  Future<List<Map<String, dynamic>>> loadAdminVouchers() async {
    final rows = await _client
        .from('vouchers')
        .select()
        .order('is_new_user_voucher', ascending: false)
        .order('created_at', ascending: false);
    final claims = await _client
        .from('voucher_claims')
        .select('voucher_id,used_at');
    final claimRows = (claims as List).cast<Map<String, dynamic>>();
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .where(
          (row) =>
              row['is_reward_voucher'] != true &&
              row['reward_id'] == null &&
              !'${row['code']}'.toUpperCase().startsWith('RW-'),
        )
        .map((row) {
          final voucherId = '${row['id']}';
          final related =
              claimRows
                  .where((claim) => '${claim['voucher_id']}' == voucherId)
                  .toList();
          return <String, dynamic>{
            ...row,
            'claim_count': related.length,
            'redeemed_count':
                related.where((claim) => claim['used_at'] != null).length,
          };
        })
        .toList();
  }

  @override
  Future<Map<String, dynamic>> createVoucher({
    required String code,
    required String title,
    required String description,
    required String discountType,
    required double discountValue,
    required double minimumSpendMyr,
    int? maxRedemptions,
    DateTime? expiresAt,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final row = <String, dynamic>{
      'id': _newVoucherId(),
      'code': code.trim().toUpperCase(),
      'title': title.trim(),
      'description': description.trim(),
      'discount_type': discountType,
      'discount_value': discountValue,
      'minimum_spend_myr':
          discountType == 'fixed'
              ? max(minimumSpendMyr, discountValue + 2)
              : minimumSpendMyr,
      'max_redemptions': maxRedemptions,
      'expires_at': expiresAt?.toUtc().toIso8601String(),
      'created_by': _client.auth.currentUser?.id,
      'is_new_user_voucher': false,
      'is_active': true,
      'created_at': now,
      'updated_at': now,
    };
    await _client.from('vouchers').insert(row);
    return row;
  }

  @override
  Future<void> setVoucherActive({
    required String voucherId,
    required bool isActive,
  }) => _client
      .from('vouchers')
      .update({
        'is_active': isActive,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      })
      .eq('id', voucherId);

  @override
  Future<Map<String, dynamic>> updateVoucher({
    required String voucherId,
    required String code,
    required String title,
    required String description,
    required String discountType,
    required double discountValue,
    required double minimumSpendMyr,
    int? maxRedemptions,
    DateTime? expiresAt,
  }) async {
    final row = <String, dynamic>{
      'id': voucherId,
      'code': code.trim().toUpperCase(),
      'title': title.trim(),
      'description': description.trim(),
      'discount_type': discountType,
      'discount_value': discountValue,
      'minimum_spend_myr':
          discountType == 'fixed'
              ? max(minimumSpendMyr, discountValue + 2)
              : minimumSpendMyr,
      'max_redemptions': maxRedemptions,
      'expires_at': expiresAt?.toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _client.from('vouchers').update(row).eq('id', voucherId);
    return row;
  }

  @override
  Future<void> deleteVoucher(String voucherId) =>
      _client.from('vouchers').delete().eq('id', voucherId);

  @override
  Future<List<Map<String, dynamic>>> loadAdminUsers() async {
    final rows = await _client
        .from('profiles')
        .select('id, email, display_name, role, created_at, updated_at')
        .order('created_at', ascending: false);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  @override
  Future<List<Map<String, dynamic>>> loadRevenueAnalytics() async {
    final rows = await _client
        .from('station_revenue_analytics')
        .select()
        .order('day', ascending: false)
        .order('revenue_myr', ascending: false);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  @override
  Future<List<Map<String, dynamic>>> loadRevenueTransactions() async {
    final payments = await _client
        .from('charging_payments')
        .select(
          'id,session_id,user_id,station_id,energy_kwh,amount_myr,status,paid_at,receipt_email',
        )
        .eq('status', 'paid')
        .order('paid_at', ascending: false)
        .limit(500);
    final stationRows = await _client.from('stations').select('id,name');
    final profileRows = await _client
        .from('profiles')
        .select('id,email,display_name');
    final sessionRows = await _client
        .from('charging_sessions')
        .select('id,pile_id,started_at,ended_at,start_soc,end_soc');
    final pileRows = await _client.from('piles').select('id,label');
    final stations = <String, String>{
      for (final row in (stationRows as List).cast<Map<String, dynamic>>())
        '${row['id']}': cleanDisplayText(row['name'] as String?),
    };
    final profiles = <String, Map<String, dynamic>>{
      for (final row in (profileRows as List).cast<Map<String, dynamic>>())
        '${row['id']}': row,
    };
    final sessions = <String, Map<String, dynamic>>{
      for (final row in (sessionRows as List).cast<Map<String, dynamic>>())
        '${row['id']}': row,
    };
    final pileLabels = <String, String>{
      for (final row in (pileRows as List).cast<Map<String, dynamic>>())
        '${row['id']}': cleanDisplayText(
          row['label'] as String?,
          fallback: 'Charging pile',
        ),
    };
    return (payments as List).cast<Map<String, dynamic>>().map((row) {
      final profile = profiles['${row['user_id']}'];
      final session = sessions['${row['session_id']}'];
      return <String, dynamic>{
        ...row,
        'station_name': stations['${row['station_id']}'] ?? row['station_id'],
        'user_email': profile?['email'] ?? 'ChargeMY user',
        'display_name': profile?['display_name'],
        'pile_id': session?['pile_id'],
        'pile_label': pileLabels['${session?['pile_id']}'] ?? 'Charging pile',
        'started_at': session?['started_at'],
        'ended_at': session?['ended_at'],
        'start_soc': session?['start_soc'],
        'end_soc': session?['end_soc'],
      };
    }).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> loadAdminActivity() async {
    final rows = await _client
        .from('admin_activity_log')
        .select()
        .order('created_at', ascending: false)
        .limit(100);
    final activities = (rows as List).cast<Map<String, dynamic>>();
    final adminIds =
        activities
            .map((row) => '${row['admin_id'] ?? ''}')
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList();
    final names = <String, String>{};
    if (adminIds.isNotEmpty) {
      final users = await _client
          .from('profiles')
          .select('id,display_name,email')
          .inFilter('id', adminIds);
      for (final user in (users as List).cast<Map<String, dynamic>>()) {
        final displayName = '${user['display_name'] ?? ''}'.trim();
        final name =
            displayName.isEmpty
                ? '${user['email'] ?? 'Administrator'}'
                : cleanDisplayText(displayName);
        names['${user['id']}'] = name;
      }
    }
    final stationRows = await _client.from('stations').select('id,name');
    final pileRows = await _client.from('piles').select('id,label,station_id');
    final stationNames = <String, String>{
      for (final station in (stationRows as List).cast<Map<String, dynamic>>())
        '${station['id']}': cleanDisplayText(
          station['name'] as String?,
          fallback: 'Charging station',
        ),
    };
    final pileLabels = <String, String>{
      for (final pile in (pileRows as List).cast<Map<String, dynamic>>())
        '${pile['id']}': cleanDisplayText(
          pile['label'] as String?,
          fallback: 'Charging pile',
        ),
    };
    return activities.map((row) {
      final details =
          (row['details'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      final stationId = '${details['station_id'] ?? ''}';
      final pileId = '${details['pile_id'] ?? ''}';
      final stationName = stationNames[stationId];
      final pileLabel = pileLabels[pileId];
      return <String, dynamic>{
        ...row,
        'admin_name': names['${row['admin_id']}'] ?? 'Administrator',
        'details': <String, dynamic>{
          ...details,
          if (stationName != null) 'station_name': stationName,
          if (pileLabel != null) 'pile_label': pileLabel,
        },
      };
    }).toList();
  }

  @override
  Future<Map<String, dynamic>?> loadStationRatingSummary(
    String stationId,
  ) async {
    final row =
        await _client
            .from('station_rating_summary')
            .select()
            .eq('station_id', stationId)
            .maybeSingle();
    return row == null ? null : (row as Map).cast<String, dynamic>();
  }

  @override
  Future<List<Map<String, dynamic>>> loadStationRatings() async {
    final ratings = await _client
        .from('station_ratings')
        .select('user_id,station_id,rating,comment,created_at,updated_at')
        .order('updated_at', ascending: false)
        .limit(500);
    final stationRows = await _client.from('stations').select('id,name');
    final stationNames = <String, String>{
      for (final row in (stationRows as List).cast<Map<String, dynamic>>())
        '${row['id']}': cleanDisplayText(
          row['name'] as String?,
          fallback: 'Charging station',
        ),
    };
    final userIds =
        (ratings as List)
            .cast<Map<String, dynamic>>()
            .map((row) => '${row['user_id'] ?? ''}')
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList();
    final reviewers = <String, Map<String, dynamic>>{};
    if (userIds.isNotEmpty) {
      final profileRows = await _client
          .from('profiles')
          .select('id,display_name,email,avatar_url')
          .inFilter('id', userIds);
      for (final profile
          in (profileRows as List).cast<Map<String, dynamic>>()) {
        final displayName = '${profile['display_name'] ?? ''}'.trim();
        reviewers['${profile['id']}'] = {
          'name':
              displayName.isEmpty
                  ? '${profile['email'] ?? 'ChargeMY user'}'
                  : cleanDisplayText(displayName),
          'avatar_url': profile['avatar_url'],
        };
      }
    }
    return (ratings as List).cast<Map<String, dynamic>>().map((row) {
      final reviewer = reviewers['${row['user_id']}'];
      return <String, dynamic>{
        ...row,
        'station_name':
            stationNames['${row['station_id']}'] ?? row['station_id'],
        'reviewer_name': reviewer?['name'] ?? 'ChargeMY user',
        'reviewer_avatar_url': reviewer?['avatar_url'],
      };
    }).toList();
  }

  @override
  Future<void> submitStationRating({
    required String stationId,
    required int rating,
    String comment = '',
  }) => _client.rpc(
    'submit_station_rating',
    params: {
      'p_station_id': stationId,
      'p_rating': rating,
      'p_comment': comment.trim(),
    },
  );

  @override
  Future<int> recordChargingPayment({
    required String sessionId,
    required double amountMyr,
    required double energyKwh,
    String? receiptEmail,
    String? voucherClaimId,
    double? originalAmountMyr,
  }) async {
    final result = await _client.rpc(
      'record_charging_payment',
      params: {
        'p_session_id': sessionId,
        'p_amount_myr': amountMyr,
        'p_energy_kwh': energyKwh,
        'p_receipt_email': receiptEmail,
        'p_voucher_claim_id': voucherClaimId,
        'p_original_amount_myr': originalAmountMyr,
      },
    );
    if (result is Map) {
      return (result['points_earned'] as num?)?.toInt() ?? 0;
    }
    if (result is List && result.isNotEmpty && result.first is Map) {
      return ((result.first as Map)['points_earned'] as num?)?.toInt() ?? 0;
    }
    return 0;
  }

  @override
  Future<void> deleteMyAccount() => _client.rpc('delete_my_account');

  @override
  Future<void> setUserRole({required String userId, required String role}) =>
      _client.rpc(
        'admin_set_user_role',
        params: {'p_user_id': userId, 'p_role': role},
      );

  @override
  Future<List<AppNotification>> loadNotifications() async {
    final rows = await _client
        .from('notification_events')
        .select()
        .order('created_at', ascending: false)
        .limit(100);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(
          (row) => AppNotification(
            id: row['id'] as String,
            type: row['type'] as String? ?? 'system',
            title: row['title'] as String? ?? 'ChargeMY update',
            body: row['body'] as String? ?? '',
            createdAt:
                DateTime.tryParse('${row['created_at']}')?.toLocal() ??
                DateTime.now(),
            readAt:
                row['read_at'] == null
                    ? null
                    : DateTime.tryParse('${row['read_at']}')?.toLocal(),
          ),
        )
        .toList();
  }

  @override
  Future<void> markNotificationRead(String notificationId) => _client
      .from('notification_events')
      .update({'read_at': DateTime.now().toUtc().toIso8601String()})
      .eq('id', notificationId);

  @override
  Future<ChargingSession> recordChargeProgress({
    required String sessionId,
    required int stateOfCharge,
    double? energyKwh,
  }) async {
    final row = await _client.rpc(
      'record_charge_progress',
      params: {
        'p_session_id': sessionId,
        'p_soc': stateOfCharge,
        'p_energy_kwh': energyKwh,
      },
    );
    return _session((row as Map).cast<String, dynamic>());
  }

  @override
  Future<ImportSummary> bulkImport({
    required String fileName,
    required String format,
    required List<Map<String, dynamic>> rows,
  }) async {
    final response = await _client.rpc(
      'admin_bulk_import',
      params: {'p_file_name': fileName, 'p_format': format, 'p_rows': rows},
    );
    final data = (response as Map).cast<String, dynamic>();
    final errors =
        (data['errors'] as List? ?? const [])
            .map(
              (entry) =>
                  entry is Map
                      ? 'Row ${entry['row']}: ${entry['error']}'
                      : '$entry',
            )
            .toList();
    return ImportSummary(
      totalRows: (data['total_rows'] as num?)?.toInt() ?? rows.length,
      importedRows: (data['imported_rows'] as num?)?.toInt() ?? 0,
      errors: errors,
    );
  }

  @override
  Future<void> updateTicketStatus(String ticketId, String status) => _client
      .from('tickets')
      .update({
        'status': status,
        if (status == 'resolved')
          'resolved_at': DateTime.now().toUtc().toIso8601String(),
      })
      .eq('id', ticketId);

  @override
  Future<ChargingSession> startCharging({
    required String stationId,
    required String pileId,
    required GeoLocation location,
    int startSoc = 20,
    int targetSoc = 80,
  }) async {
    final row = await _client.rpc(
      'start_charge_at_station',
      params: {
        'p_station_id': stationId,
        'p_pile_id': pileId,
        'p_latitude': location.latitude,
        'p_longitude': location.longitude,
        'p_start_soc': startSoc,
        'p_target_soc': targetSoc,
      },
    );
    return _session((row as Map).cast<String, dynamic>());
  }

  @override
  Future<ChargingSession> completeCharge(
    String sessionId, {
    double? energyKwh,
    int? endSoc,
  }) async {
    final row = await _client.rpc(
      'complete_charge',
      params: {
        'p_session_id': sessionId,
        'p_energy_kwh': energyKwh,
        'p_end_soc': endSoc,
      },
    );
    return _session((row as Map).cast<String, dynamic>());
  }

  @override
  Future<void> updatePileStatus({
    required String stationId,
    required String pileId,
    required PileStatus status,
  }) => _client.rpc(
    'admin_update_pile_status',
    params: {'p_pile_id': pileId, 'p_status': status.name},
  );

  @override
  Future<void> createStation({
    required String name,
    required String address,
    required double latitude,
    required double longitude,
    required String brand,
    required String indoorOutdoor,
    required String localAuthority,
    required String connectorType,
    required double powerKw,
    required double pricePerKwh,
  }) {
    final id = 'admin-${DateTime.now().millisecondsSinceEpoch}';
    return _client.rpc(
      'admin_create_station',
      params: {
        'p_station_id': id,
        'p_name': name.trim(),
        'p_address': address.trim(),
        'p_latitude': latitude,
        'p_longitude': longitude,
        'p_brand': brand.trim(),
        'p_indoor_outdoor': indoorOutdoor,
        'p_local_authority': localAuthority.trim(),
        'p_connector_type': connectorType,
        'p_power_kw': powerKw,
        'p_price_per_kwh': pricePerKwh,
      },
    );
  }

  @override
  Future<void> updateStation({
    required String stationId,
    required String name,
    required String address,
    required double latitude,
    required double longitude,
    required String brand,
    required String indoorOutdoor,
    required String localAuthority,
  }) => _client.rpc(
    'admin_update_station',
    params: {
      'p_station_id': stationId,
      'p_name': name.trim(),
      'p_address': address.trim(),
      'p_latitude': latitude,
      'p_longitude': longitude,
      'p_brand': brand.trim(),
      'p_indoor_outdoor': indoorOutdoor,
      'p_local_authority': localAuthority.trim(),
    },
  );

  @override
  Future<void> deleteStation(String stationId) =>
      _client.rpc('admin_delete_station', params: {'p_station_id': stationId});

  @override
  Future<void> createPile({
    required String stationId,
    required String label,
    required String connectorType,
    required double powerKw,
    required double pricePerKwh,
    required PileStatus status,
  }) => _client.rpc(
    'admin_create_pile',
    params: {
      'p_station_id': stationId,
      'p_pile_id': '$stationId-pile-${DateTime.now().millisecondsSinceEpoch}',
      'p_label': label.trim(),
      'p_connector_type': connectorType,
      'p_power_kw': powerKw,
      'p_price_per_kwh': pricePerKwh,
      'p_status': status.name,
    },
  );

  @override
  Future<void> updatePile({
    required String pileId,
    required String label,
    required String connectorType,
    required double powerKw,
    required double pricePerKwh,
  }) => _client.rpc(
    'admin_update_pile',
    params: {
      'p_pile_id': pileId,
      'p_label': label.trim(),
      'p_connector_type': connectorType,
      'p_power_kw': powerKw,
      'p_price_per_kwh': pricePerKwh,
    },
  );

  @override
  Future<void> deletePile(String pileId) =>
      _client.rpc('admin_delete_pile', params: {'p_pile_id': pileId});

  @override
  Future<void> createHazardReport({
    required String stationId,
    String? pileId,
    required String category,
    required String note,
    List<Uint8List> imageBytes = const [],
    List<String> imageNames = const [],
  }) async {
    if (imageBytes.length > 5) {
      throw StateError('You can attach up to five photos to one report.');
    }
    if (imageNames.length != imageBytes.length) {
      throw StateError(
        'Could not prepare the selected photos. Please try again.',
      );
    }
    final imagePaths = <String>[];
    if (imageBytes.isNotEmpty) {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) throw StateError('Sign in to upload photo evidence.');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      for (var index = 0; index < imageBytes.length; index += 1) {
        final extension = imageNames[index].split('.').last.toLowerCase();
        final safeExtension =
            ['jpg', 'jpeg', 'png', 'webp'].contains(extension)
                ? extension
                : 'jpg';
        final imagePath = '$uid/${timestamp}_$index.$safeExtension';
        await _client.storage
            .from('reports')
            .uploadBinary(
              imagePath,
              imageBytes[index],
              fileOptions: FileOptions(
                contentType:
                    safeExtension == 'png' ? 'image/png' : 'image/jpeg',
              ),
            );
        imagePaths.add(imagePath);
      }
    }
    await _client.rpc(
      'create_hazard_report',
      params: {
        'p_station_id': stationId,
        'p_pile_id': pileId ?? '',
        'p_category': category,
        'p_note': note.trim(),
        'p_image_paths': imagePaths,
      },
    );
  }

  @override
  Future<void> toggleFavourite(String stationId) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw StateError('Sign in to manage favourites.');
    final current =
        await _client
            .from('favorites')
            .select('station_id')
            .eq('user_id', uid)
            .eq('station_id', stationId)
            .maybeSingle();
    if (current == null) {
      await _client.from('favorites').insert({
        'user_id': uid,
        'station_id': stationId,
      });
    } else {
      await _client
          .from('favorites')
          .delete()
          .eq('user_id', uid)
          .eq('station_id', stationId);
    }
  }

  Future<Set<String>> _favouriteIds() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return {};
    final rows = await _client
        .from('favorites')
        .select('station_id')
        .eq('user_id', uid);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map((row) => row['station_id'] as String)
        .toSet();
  }

  ChargingPile _pile(Map<String, dynamic> row) => ChargingPile(
    id: row['id'] as String,
    stationId: row['station_id'] as String,
    label: cleanDisplayText(row['label'] as String?, fallback: 'Charging bay'),
    connectorType: cleanDisplayText(
      row['connector_type'] as String?,
      fallback: 'Unknown',
    ),
    powerKw: _double(row['power_kw'], 0),
    pricePerKwh: _double(row['price_per_kwh'], 0),
    status: _status(row['operational_state'] as String?),
    reservationSessionId: row['reservation_session_id'] as String?,
  );

  Reward _reward(Map<String, dynamic> row) => Reward(
    id: '${row['id']}',
    title: '${row['title']}',
    description: '${row['description'] ?? ''}',
    pointsRequired: (row['points_required'] as num?)?.toInt() ?? 0,
    discountMyr: _double(row['discount_myr'], 0),
    minimumSpendMyr: _double(row['minimum_spend_myr'], 0),
    isActive: row['is_active'] == true,
  );

  HazardReport _hazard(Map<String, dynamic> row) => HazardReport(
    id: row['id'] as String,
    stationId: row['station_id'] as String? ?? '',
    pileId: row['pile_id'] as String?,
    category: row['category'] as String? ?? 'Hazard report',
    note: row['note'] as String? ?? '',
    createdAt:
        row['created_at'] == null
            ? null
            : DateTime.tryParse(row['created_at'] as String)?.toLocal(),
    imagePath: row['image_path'] as String?,
    imagePaths: [
      ...((row['image_paths'] as List?)
              ?.map((path) => '$path')
              .where((path) => path.isNotEmpty) ??
          const <String>[]),
      if (row['image_paths'] == null && row['image_path'] != null)
        '${row['image_path']}',
    ],
    status:
        row['status'] == 'submitted'
            ? 'ongoing'
            : row['status'] as String? ?? 'ongoing',
  );

  MaintenanceTicket _ticket(Map<String, dynamic> row) => MaintenanceTicket(
    id: row['id'] as String,
    stationId: row['station_id'] as String,
    pileId: row['pile_id'] as String?,
    severity: row['severity'] as String? ?? 'medium',
    status: row['status'] as String? ?? 'open',
    reportCount: (row['report_ids'] as List? ?? const []).length,
    openedAt:
        row['opened_at'] == null
            ? null
            : DateTime.tryParse(row['opened_at'] as String)?.toLocal(),
  );

  ChargingSession _session(Map<String, dynamic> data) => ChargingSession(
    id: data['id'] as String,
    stationId: data['station_id'] as String,
    pileId: data['pile_id'] as String,
    expiresAt:
        data['expires_at'] == null
            ? DateTime.now().add(const Duration(hours: 12))
            : DateTime.parse(data['expires_at'] as String).toLocal(),
    isCharging: data['state'] == 'occupied',
    stateOfCharge: (data['end_soc'] as num?)?.toInt(),
    startSoc: (data['start_soc'] as num?)?.toInt(),
    targetSoc: (data['target_soc'] as num?)?.toInt(),
    chargePowerKw: _doubleOrNull(data['charge_power_kw']),
    batteryKwh: _doubleOrNull(data['battery_kwh']),
    startedAt:
        data['started_at'] == null
            ? null
            : DateTime.tryParse('${data['started_at']}')?.toLocal(),
  );

  double _double(Object? value, double fallback) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? fallback;

  double? _doubleOrNull(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value');

  PileStatus _status(String? value) {
    if (value == 'reserved') return PileStatus.occupied;
    for (final status in PileStatus.values) {
      if (status.name == value) return status;
    }
    return PileStatus.offline;
  }

  int _pileNumber(String label) =>
      int.tryParse(RegExp(r'\d+').firstMatch(label)?.group(0) ?? '') ?? 999999;
}

String _newVoucherId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex =
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
