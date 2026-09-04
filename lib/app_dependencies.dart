import 'data/repositories/supabase_station_repository.dart';
import 'data/repositories/station_repository.dart';

class AppDependencies {
  AppDependencies({StationRepository? stationRepository})
    : stationRepository = stationRepository ?? SupabaseStationRepository();

  final StationRepository stationRepository;
}
