import 'dart:async';
import 'dart:typed_data';

import '../../domain/models/charging_models.dart';
import 'station_repository.dart';

class DemoStationRepository implements StationRepository {
  DemoStationRepository() {
    _stations = _seedStations();
  }

  final _controller = StreamController<List<ChargingStation>>.broadcast();
  late List<ChargingStation> _stations;

  @override
  Stream<List<ChargingStation>> watchStations() async* {
    yield List.unmodifiable(_stations);
    yield* _controller.stream;
  }

  @override
  Stream<List<HazardReport>> watchHazardReports() => Stream.value(const []);

  @override
  Future<List<HazardReport>> loadHazardReports(List<String> stationIds) async =>
      const [];

  @override
  Future<void> updateHazardReportStatus(String reportId, String status) async {}

  @override
  Future<String?> getHazardEvidenceUrl(String imagePath) async => null;

  @override
  Future<List<MaintenanceTicket>> loadTickets() async => const [];

  @override
  Future<List<StationDailyAnalytics>> loadDailyAnalytics() async => const [];

  @override
  Future<List<Map<String, dynamic>>> loadMaintenanceCandidates() async =>
      const [];

  @override
  Future<void> markMaintenanceCandidateCompleted(String pileId) async {}

  @override
  Future<List<ChargingPayment>> loadMyPayments() async => const [];

  @override
  Future<List<Voucher>> loadMyVouchers() async => const [];

  @override
  Future<Voucher> claimVoucher(String code) async =>
      throw UnsupportedError('Use the Supabase-connected mobile app.');

  @override
  Future<RewardSummary> loadMyRewards() async =>
      const RewardSummary(pointsBalance: 0, rewards: [], history: []);

  @override
  Future<RewardSummary> redeemReward(String rewardId) async =>
      throw UnsupportedError('Use the Supabase-connected mobile app.');

  @override
  Future<List<Map<String, dynamic>>> loadAdminRewards() async => const [];

  @override
  Future<Map<String, dynamic>> createReward({
    required String title,
    required String description,
    required int pointsRequired,
    required double discountMyr,
    required double minimumSpendMyr,
  }) async => throw UnsupportedError('Use the Supabase-connected mobile app.');

  @override
  Future<Map<String, dynamic>> updateReward({
    required String rewardId,
    required String title,
    required String description,
    required int pointsRequired,
    required double discountMyr,
    required double minimumSpendMyr,
  }) async => throw UnsupportedError('Use the Supabase-connected mobile app.');

  @override
  Future<void> setRewardActive({
    required String rewardId,
    required bool isActive,
  }) async => throw UnsupportedError('Use the Supabase-connected mobile app.');

  @override
  Future<void> deleteReward(String rewardId) async =>
      throw UnsupportedError('Use the Supabase-connected mobile app.');

  @override
  Future<List<Map<String, dynamic>>> loadAdminVouchers() async => const [];

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
  }) async => throw UnsupportedError('Use the Supabase-connected mobile app.');

  @override
  Future<void> setVoucherActive({
    required String voucherId,
    required bool isActive,
  }) async => throw UnsupportedError('Use the Supabase-connected mobile app.');

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
  }) async => throw UnsupportedError('Use the Supabase-connected mobile app.');

  @override
  Future<void> deleteVoucher(String voucherId) async =>
      throw UnsupportedError('Use the Supabase-connected mobile app.');

  @override
  Future<List<Map<String, dynamic>>> loadAdminUsers() async => const [];

  @override
  Future<List<Map<String, dynamic>>> loadRevenueAnalytics() async => const [];

  @override
  Future<List<Map<String, dynamic>>> loadRevenueTransactions() async =>
      const [];

  @override
  Future<List<Map<String, dynamic>>> loadAdminActivity() async => const [];

  @override
  Future<Map<String, dynamic>?> loadStationRatingSummary(
    String stationId,
  ) async => null;

  @override
  Future<List<Map<String, dynamic>>> loadStationRatings() async => const [];

  @override
  Future<void> submitStationRating({
    required String stationId,
    required int rating,
    String comment = '',
  }) async => throw UnsupportedError('Use the Supabase-connected mobile app.');

  @override
  Future<int> recordChargingPayment({
    required String sessionId,
    required double amountMyr,
    required double energyKwh,
    String? receiptEmail,
    String? voucherClaimId,
    double? originalAmountMyr,
  }) async => amountMyr.floor();

  @override
  Future<void> deleteMyAccount() async =>
      throw UnsupportedError('Use the Supabase-connected mobile app.');

  @override
  Future<void> setUserRole({
    required String userId,
    required String role,
  }) async => throw UnsupportedError('Use the Supabase-connected mobile app.');

  @override
  Future<List<AppNotification>> loadNotifications() async => const [];

  @override
  Future<void> markNotificationRead(String notificationId) async {}

  @override
  Future<ChargingSession> recordChargeProgress({
    required String sessionId,
    required int stateOfCharge,
    double? energyKwh,
  }) async {
    for (final station in _stations) {
      for (final pile in station.piles) {
        if (pile.reservationSessionId == sessionId &&
            pile.status == PileStatus.occupied) {
          return ChargingSession(
            id: sessionId,
            stationId: station.id,
            pileId: pile.id,
            expiresAt: DateTime.now().add(const Duration(hours: 12)),
            isCharging: true,
            stateOfCharge: stateOfCharge,
          );
        }
      }
    }
    throw StateError('No active charging session exists.');
  }

  @override
  Future<ImportSummary> bulkImport({
    required String fileName,
    required String format,
    required List<Map<String, dynamic>> rows,
  }) => throw UnsupportedError('Use the Supabase-connected app.');

  @override
  Future<void> updateTicketStatus(String ticketId, String status) async {}

  @override
  Future<ChargingSession> startCharging({
    required String stationId,
    required String pileId,
    required GeoLocation location,
    int startSoc = 20,
    int targetSoc = 80,
  }) async {
    final station = _stations.firstWhere((item) => item.id == stationId);
    final pile = station.piles.firstWhere((item) => item.id == pileId);
    if (pile.status != PileStatus.available) {
      throw StateError('This charging pile is no longer available.');
    }
    final session = ChargingSession(
      id: 'charge-${DateTime.now().millisecondsSinceEpoch}',
      stationId: stationId,
      pileId: pileId,
      expiresAt: DateTime.now().add(const Duration(hours: 12)),
      isCharging: true,
      stateOfCharge: startSoc,
      startSoc: startSoc,
      targetSoc: targetSoc,
      chargePowerKw: pile.powerKw,
      batteryKwh: 60,
      startedAt: DateTime.now(),
    );
    _replacePile(
      stationId,
      pile.copyWith(
        status: PileStatus.occupied,
        reservationSessionId: session.id,
      ),
    );
    return session;
  }

  @override
  Future<ChargingSession> completeCharge(
    String sessionId, {
    double? energyKwh,
    int? endSoc,
  }) async {
    for (final station in _stations) {
      for (final pile in station.piles) {
        if (pile.reservationSessionId == sessionId) {
          _replacePile(
            station.id,
            pile.copyWith(
              status: PileStatus.available,
              reservationSessionId: null,
            ),
          );
          return ChargingSession(
            id: sessionId,
            stationId: station.id,
            pileId: pile.id,
            expiresAt: DateTime.now(),
          );
        }
      }
    }
    throw StateError('No active charge was found.');
  }

  @override
  Future<void> toggleFavourite(String stationId) async {
    _stations =
        _stations
            .map(
              (station) =>
                  station.id == stationId
                      ? station.copyWith(isFavourite: !station.isFavourite)
                      : station,
            )
            .toList();
    _emit();
  }

  @override
  Future<void> updatePileStatus({
    required String stationId,
    required String pileId,
    required PileStatus status,
  }) async {
    final station = _stations.firstWhere((item) => item.id == stationId);
    final pile = station.piles.firstWhere((item) => item.id == pileId);
    _replacePile(stationId, pile.copyWith(status: status));
  }

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
  }) async {
    throw UnsupportedError(
      'Demo data is disabled. Use the Supabase-connected mobile app.',
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
  }) async => throw UnsupportedError('Use the Supabase-connected mobile app.');

  @override
  Future<void> deleteStation(String stationId) async =>
      throw UnsupportedError('Use the Supabase-connected mobile app.');

  @override
  Future<void> createPile({
    required String stationId,
    required String label,
    required String connectorType,
    required double powerKw,
    required double pricePerKwh,
    required PileStatus status,
  }) async {
    throw UnsupportedError(
      'Demo data is disabled. Use the Supabase-connected mobile app.',
    );
  }

  @override
  Future<void> updatePile({
    required String pileId,
    required String label,
    required String connectorType,
    required double powerKw,
    required double pricePerKwh,
  }) async => throw UnsupportedError('Use the Supabase-connected mobile app.');

  @override
  Future<void> deletePile(String pileId) async =>
      throw UnsupportedError('Use the Supabase-connected mobile app.');

  @override
  Future<void> createHazardReport({
    required String stationId,
    String? pileId,
    required String category,
    required String note,
    List<Uint8List> imageBytes = const [],
    List<String> imageNames = const [],
  }) async {
    throw UnsupportedError(
      'Demo data is disabled. Use the Supabase-connected mobile app.',
    );
  }

  void _replacePile(String stationId, ChargingPile replacement) {
    _stations =
        _stations.map((station) {
          if (station.id != stationId) return station;
          return station.copyWith(
            piles:
                station.piles
                    .map(
                      (pile) => pile.id == replacement.id ? replacement : pile,
                    )
                    .toList(),
          );
        }).toList();
    _emit();
  }

  void _emit() => _controller.add(List.unmodifiable(_stations));

  List<ChargingStation> _seedStations() {
    return const [
      ChargingStation(
        id: 'klcc',
        name: 'Suria KLCC EV Hub',
        address: 'Jalan P Ramlee, Kuala Lumpur',
        location: GeoLocation(3.1579, 101.7123),
        brand: 'ChargeSini',
        indoorOutdoor: 'Indoor',
        localAuthority: 'DBKL',
        piles: [
          ChargingPile(
            id: 'klcc-1',
            stationId: 'klcc',
            label: 'Bay A1',
            connectorType: 'CCS2',
            powerKw: 120,
            pricePerKwh: 1.20,
            status: PileStatus.available,
          ),
          ChargingPile(
            id: 'klcc-2',
            stationId: 'klcc',
            label: 'Bay A2',
            connectorType: 'CCS2',
            powerKw: 120,
            pricePerKwh: 1.20,
            status: PileStatus.occupied,
          ),
          ChargingPile(
            id: 'klcc-3',
            stationId: 'klcc',
            label: 'Bay B1',
            connectorType: 'Type 2',
            powerKw: 22,
            pricePerKwh: 0.85,
            status: PileStatus.available,
          ),
        ],
      ),
      ChargingStation(
        id: 'bangi',
        name: 'Bangi Gateway Charge Point',
        address: 'Persiaran Pekeliling, Bandar Baru Bangi',
        location: GeoLocation(2.9608, 101.7573),
        brand: 'Gentari',
        indoorOutdoor: 'Outdoor',
        localAuthority: 'MPKj',
        piles: [
          ChargingPile(
            id: 'bangi-1',
            stationId: 'bangi',
            label: 'DC 01',
            connectorType: 'CCS2',
            powerKw: 60,
            pricePerKwh: 1.05,
            status: PileStatus.available,
          ),
          ChargingPile(
            id: 'bangi-2',
            stationId: 'bangi',
            label: 'AC 01',
            connectorType: 'Type 2',
            powerKw: 11,
            pricePerKwh: 0.70,
            status: PileStatus.occupied,
          ),
        ],
      ),
      ChargingStation(
        id: 'genting',
        name: 'Genting Highlands SkyAvenue',
        address: 'Genting Highlands, Pahang',
        location: GeoLocation(3.4240, 101.7933),
        brand: 'JomCharge',
        indoorOutdoor: 'Indoor',
        localAuthority: 'MPB',
        piles: [
          ChargingPile(
            id: 'genting-1',
            stationId: 'genting',
            label: 'Level P4',
            connectorType: 'CCS2',
            powerKw: 180,
            pricePerKwh: 1.35,
            status: PileStatus.maintenance,
          ),
          ChargingPile(
            id: 'genting-2',
            stationId: 'genting',
            label: 'Level P5',
            connectorType: 'CHAdeMO',
            powerKw: 50,
            pricePerKwh: 1.25,
            status: PileStatus.offline,
          ),
        ],
      ),
      ChargingStation(
        id: 'tapah',
        name: 'Tapah R&R Charge Point',
        address: 'North-South Expressway, Tapah, Perak',
        location: GeoLocation(4.1884, 101.2596),
        brand: 'ChargeSini',
        indoorOutdoor: 'Outdoor',
        localAuthority: 'MD Tapah',
        piles: [
          ChargingPile(
            id: 'tapah-1',
            stationId: 'tapah',
            label: 'DC 01',
            connectorType: 'CCS2',
            powerKw: 120,
            pricePerKwh: 1.10,
            status: PileStatus.available,
          ),
          ChargingPile(
            id: 'tapah-2',
            stationId: 'tapah',
            label: 'AC 01',
            connectorType: 'Type 2',
            powerKw: 22,
            pricePerKwh: 0.75,
            status: PileStatus.available,
          ),
        ],
      ),
      ChargingStation(
        id: 'ipoh',
        name: 'Ipoh Sentral EV Hub',
        address: 'Jalan Dato Sagor, Ipoh, Perak',
        location: GeoLocation(4.5975, 101.0901),
        brand: 'Gentari',
        indoorOutdoor: 'Indoor',
        localAuthority: 'MBI',
        piles: [
          ChargingPile(
            id: 'ipoh-1',
            stationId: 'ipoh',
            label: 'DC 01',
            connectorType: 'CCS2',
            powerKw: 180,
            pricePerKwh: 1.25,
            status: PileStatus.available,
          ),
        ],
      ),
    ];
  }
}
