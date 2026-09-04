import 'dart:typed_data';

import '../../domain/models/charging_models.dart';

abstract class StationRepository {
  Stream<List<ChargingStation>> watchStations();
  Stream<List<HazardReport>> watchHazardReports();
  Future<List<HazardReport>> loadHazardReports(List<String> stationIds);
  Future<void> updateHazardReportStatus(String reportId, String status);
  Future<String?> getHazardEvidenceUrl(String imagePath);
  Future<List<MaintenanceTicket>> loadTickets();
  Future<List<StationDailyAnalytics>> loadDailyAnalytics();
  Future<List<Map<String, dynamic>>> loadMaintenanceCandidates();
  Future<void> markMaintenanceCandidateCompleted(String pileId);
  Future<List<ChargingPayment>> loadMyPayments();
  Future<List<Voucher>> loadMyVouchers();
  Future<Voucher> claimVoucher(String code);
  Future<RewardSummary> loadMyRewards();
  Future<RewardSummary> redeemReward(String rewardId);
  Future<List<Map<String, dynamic>>> loadAdminRewards();
  Future<Map<String, dynamic>> createReward({
    required String title,
    required String description,
    required int pointsRequired,
    required double discountMyr,
    required double minimumSpendMyr,
  });
  Future<Map<String, dynamic>> updateReward({
    required String rewardId,
    required String title,
    required String description,
    required int pointsRequired,
    required double discountMyr,
    required double minimumSpendMyr,
  });
  Future<void> setRewardActive({
    required String rewardId,
    required bool isActive,
  });
  Future<void> deleteReward(String rewardId);
  Future<List<Map<String, dynamic>>> loadAdminVouchers();
  Future<Map<String, dynamic>> createVoucher({
    required String code,
    required String title,
    required String description,
    required String discountType,
    required double discountValue,
    required double minimumSpendMyr,
    int? maxRedemptions,
    DateTime? expiresAt,
  });
  Future<void> setVoucherActive({
    required String voucherId,
    required bool isActive,
  });
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
  });
  Future<void> deleteVoucher(String voucherId);
  Future<List<Map<String, dynamic>>> loadAdminUsers();
  Future<List<Map<String, dynamic>>> loadRevenueAnalytics();
  Future<List<Map<String, dynamic>>> loadRevenueTransactions();
  Future<List<Map<String, dynamic>>> loadAdminActivity();
  Future<Map<String, dynamic>?> loadStationRatingSummary(String stationId);
  Future<List<Map<String, dynamic>>> loadStationRatings();
  Future<void> submitStationRating({
    required String stationId,
    required int rating,
    String comment,
  });
  Future<int> recordChargingPayment({
    required String sessionId,
    required double amountMyr,
    required double energyKwh,
    String? receiptEmail,
    String? voucherClaimId,
    double? originalAmountMyr,
  });
  Future<void> deleteMyAccount();
  Future<void> setUserRole({required String userId, required String role});
  Future<List<AppNotification>> loadNotifications();
  Future<void> markNotificationRead(String notificationId);
  Future<ChargingSession> recordChargeProgress({
    required String sessionId,
    required int stateOfCharge,
    double? energyKwh,
  });
  Future<ImportSummary> bulkImport({
    required String fileName,
    required String format,
    required List<Map<String, dynamic>> rows,
  });
  Future<void> updateTicketStatus(String ticketId, String status);
  Future<ChargingSession> startCharging({
    required String stationId,
    required String pileId,
    required GeoLocation location,
    int startSoc = 20,
    int targetSoc = 80,
  });
  Future<ChargingSession> completeCharge(
    String sessionId, {
    double? energyKwh,
    int? endSoc,
  });
  Future<void> updatePileStatus({
    required String stationId,
    required String pileId,
    required PileStatus status,
  });
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
  });
  Future<void> updateStation({
    required String stationId,
    required String name,
    required String address,
    required double latitude,
    required double longitude,
    required String brand,
    required String indoorOutdoor,
    required String localAuthority,
  });
  Future<void> deleteStation(String stationId);
  Future<void> createPile({
    required String stationId,
    required String label,
    required String connectorType,
    required double powerKw,
    required double pricePerKwh,
    required PileStatus status,
  });
  Future<void> updatePile({
    required String pileId,
    required String label,
    required String connectorType,
    required double powerKw,
    required double pricePerKwh,
  });
  Future<void> deletePile(String pileId);
  Future<void> createHazardReport({
    required String stationId,
    String? pileId,
    required String category,
    required String note,
    List<Uint8List> imageBytes = const [],
    List<String> imageNames = const [],
  });
  Future<void> toggleFavourite(String stationId);
}
