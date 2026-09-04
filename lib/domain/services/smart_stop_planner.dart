import 'dart:math' as math;

import '../models/charging_models.dart';

class JourneyPlan {
  const JourneyPlan({
    required this.distanceKm,
    required this.estimatedEnergyKwh,
    required this.stops,
    required this.canReachDestination,
  });

  final double distanceKm;
  final double estimatedEnergyKwh;
  final List<SmartStop> stops;
  final bool canReachDestination;
}

class SmartStop {
  const SmartStop({
    required this.station,
    required this.pile,
    required this.distanceFromOriginKm,
    required this.arrivalSoc,
    required this.recommendedDepartureSoc,
    required this.chargeMinutes,
  });

  final ChargingStation station;
  final ChargingPile pile;
  final double distanceFromOriginKm;
  final int arrivalSoc;
  final int recommendedDepartureSoc;
  final int chargeMinutes;
}

class SmartStopPlanner {
  const SmartStopPlanner._();

  static const _roadDistanceFactor = 1.16;
  static const _maximumCorridorDetourKm = 32.0;
  static const _suggestStopAtOrBelowSoc = 60;

  static JourneyPlan plan({
    required GeoLocation origin,
    required GeoLocation destination,
    required int currentSoc,
    required VehicleProfile vehicle,
    required List<ChargingStation> stations,
    double? routeDistanceKm,
    double? elevationGainM,
    Set<String> excludedStationIds = const {},
  }) {
    final directDistance =
        routeDistanceKm ??
        _distanceKm(origin, destination) * _roadDistanceFactor;
    final reserveEnergy = vehicle.batteryKwh * vehicle.reserveSoc / 100;
    final directEnergy =
        _energyForKm(directDistance, vehicle) + (elevationGainM ?? 0) / 1000;
    final stops = <SmartStop>[];
    final visited = <String>{};
    var currentLocation = origin;
    var currentSocValue = currentSoc;
    var travelledKm = 0.0;
    var canReachDestination = false;

    for (var leg = 0; leg < 4; leg += 1) {
      final energyNow = vehicle.batteryKwh * currentSocValue / 100;
      final usableEnergy = math.max(0, energyNow - reserveEnergy);
      final distanceToDestination =
          _distanceKm(currentLocation, destination) * _roadDistanceFactor;
      if (_energyForKm(distanceToDestination, vehicle) <= usableEnergy) {
        canReachDestination = true;
        break;
      }

      final candidates = <_Candidate>[];
      for (final station in stations) {
        if (visited.contains(station.id) ||
            excludedStationIds.contains(station.id)) {
          continue;
        }
        final pile = _bestCompatiblePile(station, vehicle);
        if (pile == null) continue;
        final legDistance =
            _distanceKm(currentLocation, station.location) *
            _roadDistanceFactor;
        final remainingDistance =
            _distanceKm(station.location, destination) * _roadDistanceFactor;
        final corridorDetour =
            travelledKm + legDistance + remainingDistance - directDistance;
        if (_energyForKm(legDistance, vehicle) > usableEnergy ||
            remainingDistance >= distanceToDestination - 4 ||
            corridorDetour > _maximumCorridorDetourKm) {
          continue;
        }
        final predictedArrivalSoc =
            ((energyNow - _energyForKm(legDistance, vehicle)) /
                    vehicle.batteryKwh *
                    100)
                .floor();
        if (predictedArrivalSoc > _suggestStopAtOrBelowSoc) continue;
        candidates.add(
          _Candidate(
            station: station,
            pile: pile,
            legDistanceKm: legDistance,
            remainingDistanceKm: remainingDistance,
            estimatedTotalMinutes: _estimateTotalMinutes(
              legDistanceKm: legDistance,
              remainingDistanceKm: remainingDistance,
              arrivalEnergyKwh: energyNow - _energyForKm(legDistance, vehicle),
              pilePowerKw: pile.powerKw,
              vehicle: vehicle,
              reserveEnergyKwh: reserveEnergy,
            ),
          ),
        );
      }
      if (candidates.isEmpty) break;
      candidates.sort((left, right) {
        final time = left.estimatedTotalMinutes.compareTo(
          right.estimatedTotalMinutes,
        );
        if (time != 0) return time;
        return left.remainingDistanceKm.compareTo(right.remainingDistanceKm);
      });
      final chosen = candidates.first;
      final arrivalEnergy =
          energyNow - _energyForKm(chosen.legDistanceKm, vehicle);
      final energyNeededAfterStop =
          _energyForKm(chosen.remainingDistanceKm, vehicle) + reserveEnergy;
      final departureEnergy = math.min(
        vehicle.batteryKwh,
        math.max(energyNeededAfterStop, vehicle.batteryKwh * 0.8),
      );
      final arrivalSoc =
          (arrivalEnergy / vehicle.batteryKwh * 100)
              .floor()
              .clamp(0, 100)
              .toInt();
      final departureSoc =
          (departureEnergy / vehicle.batteryKwh * 100)
              .ceil()
              .clamp(0, 100)
              .toInt();
      final chargeMinutes =
          estimateChargingDuration(
            batteryKwh: vehicle.batteryKwh,
            stationPowerKw:
                math
                    .min(chosen.pile.powerKw, vehicle.maxChargePowerKw)
                    .toDouble(),
            startSoc: arrivalSoc,
            targetSoc: departureSoc,
          ).inMinutes.clamp(1, 240).toInt();
      stops.add(
        SmartStop(
          station: chosen.station,
          pile: chosen.pile,
          distanceFromOriginKm: travelledKm + chosen.legDistanceKm,
          arrivalSoc: arrivalSoc,
          recommendedDepartureSoc:
              departureSoc.clamp(vehicle.reserveSoc, 100).toInt(),
          chargeMinutes: chargeMinutes,
        ),
      );
      visited.add(chosen.station.id);
      currentLocation = chosen.station.location;
      travelledKm += chosen.legDistanceKm;
      currentSocValue = (departureEnergy / vehicle.batteryKwh * 100).round();
    }
    return JourneyPlan(
      distanceKm: directDistance,
      estimatedEnergyKwh: directEnergy,
      stops: stops,
      canReachDestination: canReachDestination,
    );
  }

  static ChargingPile? _bestCompatiblePile(
    ChargingStation station,
    VehicleProfile vehicle,
  ) {
    final compatible =
        station.piles
            .where(
              (pile) =>
                  pile.status == PileStatus.available &&
                  vehicle.connectorTypes.contains(pile.connectorType),
            )
            .toList()
          ..sort((left, right) => right.powerKw.compareTo(left.powerKw));
    return compatible.isEmpty ? null : compatible.first;
  }

  static double _energyForKm(double distanceKm, VehicleProfile vehicle) {
    return distanceKm * vehicle.efficiencyWhPerKm / 1000;
  }

  static int _estimateTotalMinutes({
    required double legDistanceKm,
    required double remainingDistanceKm,
    required double arrivalEnergyKwh,
    required double pilePowerKw,
    required VehicleProfile vehicle,
    required double reserveEnergyKwh,
  }) {
    final energyNeeded =
        _energyForKm(remainingDistanceKm, vehicle) + reserveEnergyKwh;
    final departureEnergy = math.min(
      vehicle.batteryKwh,
      math.max(energyNeeded, vehicle.batteryKwh * 0.8),
    );
    final effectivePower =
        math.max(1, math.min(pilePowerKw, vehicle.maxChargePowerKw)).toDouble();
    final arrivalSoc =
        (arrivalEnergyKwh / vehicle.batteryKwh * 100)
            .floor()
            .clamp(0, 100)
            .toInt();
    final departureSoc =
        (departureEnergy / vehicle.batteryKwh * 100)
            .ceil()
            .clamp(0, 100)
            .toInt();
    final chargeMinutes =
        estimateChargingDuration(
          batteryKwh: vehicle.batteryKwh,
          stationPowerKw: effectivePower,
          startSoc: arrivalSoc,
          targetSoc: departureSoc,
        ).inMinutes;
    final driveMinutes =
        ((legDistanceKm + remainingDistanceKm) / 55 * 60).ceil();
    return driveMinutes + chargeMinutes;
  }

  static double _distanceKm(GeoLocation first, GeoLocation second) {
    const earthRadiusKm = 6371.0;
    final latitudeDelta = _radians(second.latitude - first.latitude);
    final longitudeDelta = _radians(second.longitude - first.longitude);
    final a =
        math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
        math.cos(_radians(first.latitude)) *
            math.cos(_radians(second.latitude)) *
            math.sin(longitudeDelta / 2) *
            math.sin(longitudeDelta / 2);
    return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _radians(double degrees) => degrees * math.pi / 180;
}

class _Candidate {
  const _Candidate({
    required this.station,
    required this.pile,
    required this.legDistanceKm,
    required this.remainingDistanceKm,
    required this.estimatedTotalMinutes,
  });

  final ChargingStation station;
  final ChargingPile pile;
  final double legDistanceKm;
  final double remainingDistanceKm;
  final int estimatedTotalMinutes;
}
