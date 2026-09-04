import 'package:flutter_test/flutter_test.dart';

import 'package:chargemy/data/repositories/demo_station_repository.dart';
import 'package:chargemy/domain/models/charging_models.dart';

void main() {
  test('starts charging and occupies an available pile', () async {
    final repository = DemoStationRepository();
    final before = await repository.watchStations().first;
    final pile = before.first.piles.firstWhere(
      (item) => item.status == PileStatus.available,
    );

    final session = await repository.startCharging(
      stationId: before.first.id,
      pileId: pile.id,
      location: before.first.location,
    );
    final after = await repository.watchStations().first;
    final occupied = after.first.piles.firstWhere((item) => item.id == pile.id);

    expect(session.isCharging, isTrue);
    expect(occupied.status, PileStatus.occupied);
    expect(occupied.reservationSessionId, session.id);
  });
}
