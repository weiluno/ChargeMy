import 'package:flutter_test/flutter_test.dart';

import 'package:chargemy/domain/models/charging_models.dart';
import 'package:chargemy/domain/services/smart_stop_planner.dart';

void main() {
  const vehicle = VehicleProfile(
    id: 'test-vehicle',
    make: 'Test',
    model: 'EV',
    batteryKwh: 60,
    efficiencyWhPerKm: 160,
    connectorTypes: {'CCS2'},
    reserveSoc: 15,
  );

  test('selects a reachable compatible available stop', () {
    const station = ChargingStation(
      id: 'route-stop',
      name: 'Route stop',
      address: 'Test address',
      location: GeoLocation(0, 1),
      brand: 'Test brand',
      indoorOutdoor: 'Outdoor',
      localAuthority: 'Test authority',
      piles: [
        ChargingPile(
          id: 'route-pile',
          stationId: 'route-stop',
          label: 'DC 01',
          connectorType: 'CCS2',
          powerKw: 120,
          pricePerKwh: 1,
          status: PileStatus.available,
        ),
      ],
    );

    final plan = SmartStopPlanner.plan(
      origin: const GeoLocation(0, 0),
      destination: const GeoLocation(0, 3),
      currentSoc: 50,
      vehicle: vehicle,
      stations: const [station],
    );

    expect(plan.canReachDestination, isTrue);
    expect(plan.stops, hasLength(1));
    expect(plan.stops.single.station.id, station.id);
    expect(plan.stops.single.recommendedDepartureSoc, greaterThan(50));
  });

  test('does not select an incompatible pile', () {
    const station = ChargingStation(
      id: 'incompatible',
      name: 'Incompatible stop',
      address: 'Test address',
      location: GeoLocation(0, 1),
      brand: 'Test brand',
      indoorOutdoor: 'Outdoor',
      localAuthority: 'Test authority',
      piles: [
        ChargingPile(
          id: 'chademo-pile',
          stationId: 'incompatible',
          label: 'DC 01',
          connectorType: 'CHAdeMO',
          powerKw: 50,
          pricePerKwh: 1,
          status: PileStatus.available,
        ),
      ],
    );

    final plan = SmartStopPlanner.plan(
      origin: const GeoLocation(0, 0),
      destination: const GeoLocation(0, 3),
      currentSoc: 50,
      vehicle: vehicle,
      stations: const [station],
    );

    expect(plan.canReachDestination, isFalse);
    expect(plan.stops, isEmpty);
  });
}
