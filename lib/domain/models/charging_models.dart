import 'dart:convert';
import 'dart:math' as math;

String cleanDisplayText(String? value, {String fallback = ''}) {
  var text = value ?? fallback;
  for (var attempt = 0; attempt < 2; attempt++) {
    if (!text.contains('Ã') && !text.contains('Â') && !text.contains('â')) {
      break;
    }
    try {
      final repaired = utf8.decode(latin1.encode(text));
      if (_mojibakeScore(repaired) >= _mojibakeScore(text)) break;
      text = repaired;
    } catch (_) {
      break;
    }
  }
  const replacements = {
    'Ã‚Â·': '·',
    'Â·': '·',
    'Â ': ' ',
    'â€™': '’',
    'â€˜': '‘',
    'â€œ': '“',
    'â€': '”',
    'â€¢': '•',
    'â€“': '–',
    'â€”': '—',
    'â€¦': '…',
    'â€¯': ' ',
    'â†’': '→',
    'â†�': '←',
    'â‰¤': '≤',
    'Ã©': 'é',
    'Ã¨': 'è',
    'Ã´': 'ô',
    'Ã‚': '',
  };
  for (final entry in replacements.entries) {
    text = text.replaceAll(entry.key, entry.value);
  }
  return text
      .replaceAll('\u00A0', ' ')
      .replaceAll('\u200B', '')
      .replaceAll('\uFEFF', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

int _mojibakeScore(String value) => RegExp(r'[ÃÂâ]').allMatches(value).length;

enum PileStatus { available, reserved, occupied, offline, maintenance }

enum UserRole { guest, user, admin }

class GeoLocation {
  const GeoLocation(this.latitude, this.longitude, {this.address});

  final double latitude;
  final double longitude;
  final String? address;
}

class VehicleProfile {
  const VehicleProfile({
    required this.id,
    required this.make,
    required this.model,
    required this.batteryKwh,
    required this.efficiencyWhPerKm,
    required this.connectorTypes,
    this.targetSoc = 80,
    this.reserveSoc = 15,
  });

  final String id;
  final String make;
  final String model;
  final double batteryKwh;
  final double efficiencyWhPerKm;
  final Set<String> connectorTypes;
  final int targetSoc;
  final int reserveSoc;

  String get displayName => '$make $model';
  double get rangeKm => batteryKwh * 1000 / efficiencyWhPerKm;

  double get maxChargePowerKw {
    final name = model.toLowerCase();
    if (name.contains('e.mas 5')) return 100;
    if (name.contains('e.mas 7')) return 160;
    if (name.contains('model 3 rwd')) return 170;
    if (name.contains('model 3')) return 250;
    if (name.contains('model y rwd')) return 170;
    if (name.contains('model y')) return 250;
    if (name.contains('model s') || name.contains('model x')) return 250;
    if (name.contains('e-2008')) return 100;
    if (name.contains('e-3008')) return 160;
    return 150;
  }
}

class ChargingPile {
  const ChargingPile({
    required this.id,
    required this.stationId,
    required this.label,
    required this.connectorType,
    required this.powerKw,
    required this.pricePerKwh,
    required this.status,
    this.reservationSessionId,
  });

  final String id;
  final String stationId;
  final String label;
  final String connectorType;
  final double powerKw;
  final double pricePerKwh;
  final PileStatus status;
  final String? reservationSessionId;

  ChargingPile copyWith({
    String? label,
    PileStatus? status,
    String? reservationSessionId,
  }) {
    return ChargingPile(
      id: id,
      stationId: stationId,
      label: label ?? this.label,
      connectorType: connectorType,
      powerKw: powerKw,
      pricePerKwh: pricePerKwh,
      status: status ?? this.status,
      reservationSessionId: reservationSessionId,
    );
  }
}

class ChargingStation {
  const ChargingStation({
    required this.id,
    required this.name,
    required this.address,
    required this.location,
    required this.brand,
    required this.indoorOutdoor,
    required this.localAuthority,
    required this.piles,
    this.isFavourite = false,
  });

  final String id;
  final String name;
  final String address;
  final GeoLocation location;
  final String brand;
  final String indoorOutdoor;
  final String localAuthority;
  final List<ChargingPile> piles;
  final bool isFavourite;

  int get availableCount =>
      piles.where((pile) => pile.status == PileStatus.available).length;
  int get activeCount =>
      piles
          .where(
            (pile) =>
                pile.status == PileStatus.reserved ||
                pile.status == PileStatus.occupied,
          )
          .length;
  double get lowestPrice {
    if (piles.isEmpty) return 0;
    return piles
        .map((pile) => pile.pricePerKwh)
        .reduce((current, next) => current < next ? current : next);
  }

  Set<String> get connectorTypes =>
      piles.map((pile) => pile.connectorType).toSet();
  PileStatus get mapStatus {
    if (availableCount > 0) return PileStatus.available;
    if (activeCount > 0) return PileStatus.occupied;
    if (piles.any((pile) => pile.status == PileStatus.maintenance)) {
      return PileStatus.maintenance;
    }
    return PileStatus.offline;
  }

  ChargingStation copyWith({List<ChargingPile>? piles, bool? isFavourite}) {
    return ChargingStation(
      id: id,
      name: name,
      address: address,
      location: location,
      brand: brand,
      indoorOutdoor: indoorOutdoor,
      localAuthority: localAuthority,
      piles: piles ?? this.piles,
      isFavourite: isFavourite ?? this.isFavourite,
    );
  }
}

class ChargingSession {
  const ChargingSession({
    required this.id,
    required this.stationId,
    required this.pileId,
    required this.expiresAt,
    this.isCharging = false,
    this.stateOfCharge,
    this.startSoc,
    this.targetSoc,
    this.chargePowerKw,
    this.batteryKwh,
    this.startedAt,
  });

  final String id;
  final String stationId;
  final String pileId;
  final DateTime expiresAt;
  final bool isCharging;
  final int? stateOfCharge;
  final int? startSoc;
  final int? targetSoc;
  final double? chargePowerKw;
  final double? batteryKwh;
  final DateTime? startedAt;

  ChargingSession copyWith({
    bool? isCharging,
    int? stateOfCharge,
    int? startSoc,
    int? targetSoc,
    double? chargePowerKw,
    double? batteryKwh,
    DateTime? startedAt,
  }) => ChargingSession(
    id: id,
    stationId: stationId,
    pileId: pileId,
    expiresAt: expiresAt,
    isCharging: isCharging ?? this.isCharging,
    stateOfCharge: stateOfCharge ?? this.stateOfCharge,
    startSoc: startSoc ?? this.startSoc,
    targetSoc: targetSoc ?? this.targetSoc,
    chargePowerKw: chargePowerKw ?? this.chargePowerKw,
    batteryKwh: batteryKwh ?? this.batteryKwh,
    startedAt: startedAt ?? this.startedAt,
  );

  int get effectiveTargetSoc => targetSoc ?? 80;

  double get progress {
    final current = (stateOfCharge ?? startSoc ?? 0).clamp(0, 100);
    final target = effectiveTargetSoc.clamp(1, 100);
    if (target <= (startSoc ?? 0)) return 1;
    return ((current - (startSoc ?? 0)) / (target - (startSoc ?? 0))).clamp(
      0.0,
      1.0,
    );
  }

  Duration? get estimatedRemaining {
    final power = chargePowerKw;
    final capacity = batteryKwh;
    if (power == null || power <= 0 || capacity == null || capacity <= 0) {
      return null;
    }
    final current = (stateOfCharge ?? startSoc ?? 0).clamp(0, 100).toDouble();
    return estimateChargingDuration(
      batteryKwh: capacity,
      stationPowerKw: power,
      startSoc: current.round(),
      targetSoc: effectiveTargetSoc,
    );
  }
}

double chargingTaperFactor(double soc) {
  if (soc < 50) return .95;
  if (soc < 80) return .85;
  if (soc < 90) return .55;
  return .30;
}

Duration estimateChargingDuration({
  required double batteryKwh,
  required double stationPowerKw,
  required int startSoc,
  required int targetSoc,
}) {
  if (batteryKwh <= 0 || stationPowerKw <= 0 || targetSoc <= startSoc) {
    return Duration.zero;
  }
  var minutes = 0.0;
  var soc = startSoc.toDouble().clamp(0.0, 100.0).toDouble();
  final target = targetSoc.toDouble().clamp(0.0, 100.0).toDouble();
  while (soc < target - .0001) {
    final nextBoundary =
        soc < 50
            ? 50.0
            : soc < 80
            ? 80.0
            : soc < 90
            ? 90.0
            : 100.0;
    final segmentEnd = math.min(target, nextBoundary).toDouble();
    final energyKwh = batteryKwh * (segmentEnd - soc) / 100;
    minutes += energyKwh / (stationPowerKw * chargingTaperFactor(soc)) * 60;
    soc = segmentEnd;
  }
  return Duration(minutes: minutes.ceil());
}

int socAfterCharging({
  required double batteryKwh,
  required double stationPowerKw,
  required int startSoc,
  required int targetSoc,
  required Duration elapsed,
}) {
  return socAfterChargingPrecise(
    batteryKwh: batteryKwh,
    stationPowerKw: stationPowerKw,
    startSoc: startSoc,
    targetSoc: targetSoc,
    elapsed: elapsed,
  ).floor().clamp(startSoc, targetSoc);
}

double socAfterChargingPrecise({
  required double batteryKwh,
  required double stationPowerKw,
  required int startSoc,
  required int targetSoc,
  required Duration elapsed,
}) {
  if (batteryKwh <= 0 || stationPowerKw <= 0 || targetSoc <= startSoc) {
    return targetSoc.toDouble();
  }
  var remainingMinutes = elapsed.inMilliseconds / 60000;
  var soc = startSoc.toDouble().clamp(0.0, 100.0).toDouble();
  final target = targetSoc.toDouble().clamp(0.0, 100.0).toDouble();
  while (soc < target - .0001 && remainingMinutes > 0) {
    final nextBoundary =
        soc < 50
            ? 50.0
            : soc < 80
            ? 80.0
            : soc < 90
            ? 90.0
            : 100.0;
    final segmentEnd = math.min(target, nextBoundary).toDouble();
    final socAvailable = segmentEnd - soc;
    final socPerMinute =
        stationPowerKw * chargingTaperFactor(soc) / batteryKwh * 100 / 60;
    final segmentMinutes = socAvailable / socPerMinute;
    if (remainingMinutes < segmentMinutes) {
      soc += remainingMinutes * socPerMinute;
      remainingMinutes = 0;
    } else {
      soc = segmentEnd;
      remainingMinutes -= segmentMinutes;
    }
  }
  return soc.clamp(startSoc.toDouble(), targetSoc.toDouble());
}

class HazardReport {
  const HazardReport({
    required this.id,
    required this.stationId,
    required this.pileId,
    required this.category,
    required this.note,
    required this.createdAt,
    this.imagePath,
    this.imagePaths = const [],
    this.status = 'submitted',
  });

  final String id;
  final String stationId;
  final String? pileId;
  final String category;
  final String note;
  final DateTime? createdAt;
  final String? imagePath;
  final List<String> imagePaths;
  final String status;
}

class MaintenanceTicket {
  const MaintenanceTicket({
    required this.id,
    required this.stationId,
    required this.pileId,
    required this.severity,
    required this.status,
    required this.reportCount,
    required this.openedAt,
  });

  final String id;
  final String stationId;
  final String? pileId;
  final String severity;
  final String status;
  final int reportCount;
  final DateTime? openedAt;
}

class StationDailyAnalytics {
  const StationDailyAnalytics({
    required this.stationId,
    required this.day,
    required this.completedSessions,
    this.averageStayMinutes,
  });

  final String stationId;
  final DateTime day;
  final int completedSessions;
  final double? averageStayMinutes;
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.readAt,
  });

  final String id;
  final String type;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isRead => readAt != null;
}

class ChargingPayment {
  const ChargingPayment({
    required this.id,
    required this.sessionId,
    required this.stationId,
    required this.stationName,
    required this.energyKwh,
    required this.amountMyr,
    required this.status,
    required this.paidAt,
    this.receiptEmail,
  });

  final String id;
  final String sessionId;
  final String stationId;
  final String stationName;
  final double energyKwh;
  final double amountMyr;
  final String status;
  final DateTime paidAt;
  final String? receiptEmail;
}

class Voucher {
  const Voucher({
    required this.claimId,
    required this.code,
    required this.title,
    required this.discountType,
    required this.discountValue,
    required this.minimumSpendMyr,
    required this.claimedAt,
    this.description = '',
    this.expiresAt,
    this.usedAt,
    this.isActive = true,
    this.isRewardVoucher = false,
  });

  final String claimId;
  final String code;
  final String title;
  final String description;
  final String discountType;
  final double discountValue;
  final double minimumSpendMyr;
  final DateTime claimedAt;
  final DateTime? expiresAt;
  final DateTime? usedAt;
  final bool isActive;
  final bool isRewardVoucher;

  bool get isUsed => usedAt != null;

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  bool get isAvailable => isActive && !isUsed && !isExpired;

  double get effectiveMinimumSpendMyr =>
      discountType == 'fixed'
          ? math.max(minimumSpendMyr, discountValue + 2)
          : minimumSpendMyr;

  bool isEligibleFor(double amountMyr) =>
      isAvailable && amountMyr + .0001 >= effectiveMinimumSpendMyr;

  double discountFor(double amountMyr) {
    if (!isEligibleFor(amountMyr)) return 0;
    final discount =
        discountType == 'percent'
            ? amountMyr * discountValue / 100
            : discountValue;
    return discount.clamp(0, amountMyr).toDouble();
  }

  bool canApplyToStripePayment(double amountMyr) =>
      isEligibleFor(amountMyr) &&
      amountMyr - discountFor(amountMyr) >= 2 - .0001;

  String get discountLabel =>
      discountType == 'percent'
          ? '${discountValue.toStringAsFixed(0)}% off'
          : 'RM ${discountValue.toStringAsFixed(2)} off';
}

class Reward {
  const Reward({
    required this.id,
    required this.title,
    required this.description,
    required this.pointsRequired,
    required this.discountMyr,
    required this.minimumSpendMyr,
    required this.isActive,
  });

  final String id;
  final String title;
  final String description;
  final int pointsRequired;
  final double discountMyr;
  final double minimumSpendMyr;
  final bool isActive;

  double get effectiveMinimumSpendMyr =>
      math.max(minimumSpendMyr, discountMyr + 2);
}

class RewardRedemption {
  const RewardRedemption({
    required this.id,
    required this.rewardTitle,
    required this.pointsSpent,
    required this.discountMyr,
    required this.voucherCode,
    required this.redeemedAt,
  });

  final String id;
  final String rewardTitle;
  final int pointsSpent;
  final double discountMyr;
  final String voucherCode;
  final DateTime redeemedAt;
}

class RewardSummary {
  const RewardSummary({
    required this.pointsBalance,
    required this.rewards,
    required this.history,
  });

  final int pointsBalance;
  final List<Reward> rewards;
  final List<RewardRedemption> history;
}

class ImportSummary {
  const ImportSummary({
    required this.totalRows,
    required this.importedRows,
    required this.errors,
  });

  final int totalRows;
  final int importedRows;
  final List<String> errors;
}
