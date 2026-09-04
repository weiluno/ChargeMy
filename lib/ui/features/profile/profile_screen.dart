import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../../domain/models/charging_models.dart';
import '../../core/app_state.dart';
import '../../core/widgets.dart';

class _EvCatalogEntry {
  const _EvCatalogEntry({
    required this.brand,
    required this.model,
    required this.batteryKwh,
    required this.rangeKm,
    required this.connectors,
  });

  final String brand;
  final String model;
  final double batteryKwh;
  final double rangeKm;
  final Set<String> connectors;
}

const _evCatalog = <_EvCatalogEntry>[
  _EvCatalogEntry(
    brand: 'Proton',
    model: 'e.MAS 5 Standard',
    batteryKwh: 30.12,
    rangeKm: 225,
    connectors: {'CCS2', 'Type 2'},
  ),
  _EvCatalogEntry(
    brand: 'Proton',
    model: 'e.MAS 5 Premium',
    batteryKwh: 40.16,
    rangeKm: 325,
    connectors: {'CCS2', 'Type 2'},
  ),
  _EvCatalogEntry(
    brand: 'Proton',
    model: 'e.MAS 7 Prime',
    batteryKwh: 49.7,
    rangeKm: 345,
    connectors: {'CCS2', 'Type 2'},
  ),
  _EvCatalogEntry(
    brand: 'Proton',
    model: 'e.MAS 7 Premium',
    batteryKwh: 60.2,
    rangeKm: 410,
    connectors: {'CCS2', 'Type 2'},
  ),
  _EvCatalogEntry(
    brand: 'Tesla',
    model: 'Model 3 RWD',
    batteryKwh: 60,
    rangeKm: 534,
    connectors: {'CCS2', 'Type 2'},
  ),
  _EvCatalogEntry(
    brand: 'Tesla',
    model: 'Model 3 Long Range RWD',
    batteryKwh: 79,
    rangeKm: 750,
    connectors: {'CCS2', 'Type 2'},
  ),
  _EvCatalogEntry(
    brand: 'Tesla',
    model: 'Model 3 Performance',
    batteryKwh: 79,
    rangeKm: 571,
    connectors: {'CCS2', 'Type 2'},
  ),
  _EvCatalogEntry(
    brand: 'Tesla',
    model: 'Model Y RWD',
    batteryKwh: 60,
    rangeKm: 488,
    connectors: {'CCS2', 'Type 2'},
  ),
  _EvCatalogEntry(
    brand: 'Tesla',
    model: 'Model Y Long Range RWD',
    batteryKwh: 79,
    rangeKm: 661,
    connectors: {'CCS2', 'Type 2'},
  ),
  _EvCatalogEntry(
    brand: 'Tesla',
    model: 'Model Y L AWD',
    batteryKwh: 82,
    rangeKm: 681,
    connectors: {'CCS2', 'Type 2'},
  ),
  _EvCatalogEntry(
    brand: 'Tesla',
    model: 'Model S Dual Motor',
    batteryKwh: 100,
    rangeKm: 634,
    connectors: {'CCS2', 'Type 2'},
  ),
  _EvCatalogEntry(
    brand: 'Tesla',
    model: 'Model X Dual Motor',
    batteryKwh: 100,
    rangeKm: 576,
    connectors: {'CCS2', 'Type 2'},
  ),
  _EvCatalogEntry(
    brand: 'Peugeot',
    model: 'e-2008',
    batteryKwh: 50,
    rangeKm: 345,
    connectors: {'CHAdeMO', 'Type 2'},
  ),
  _EvCatalogEntry(
    brand: 'Peugeot',
    model: 'e-3008',
    batteryKwh: 73,
    rangeKm: 510,
    connectors: {'CHAdeMO', 'Type 2'},
  ),
];

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final vehicle = session.vehicle;
    final stations = ref.watch(stationsProvider);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Return to client map',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home?view=user'),
        ),
        title: const Text('My EV profile'),
        actions: [
          if (session.isAdmin)
            IconButton(
              tooltip: 'Admin dashboard',
              icon: const Icon(Icons.dashboard_outlined),
              onPressed: () => context.go('/admin'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (!session.isAuthenticated)
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('Sign in to save your profile'),
                trailing: FilledButton(
                  onPressed: () => context.push('/auth'),
                  child: const Text('Sign in'),
                ),
              ),
            ),
          if (session.isAuthenticated)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => _pickAvatar(context, ref),
                      child: CircleAvatar(
                        radius: 30,
                        backgroundImage:
                            session.avatarUrl == null
                                ? null
                                : NetworkImage(session.avatarUrl!),
                        child:
                            session.avatarUrl == null
                                ? const Icon(Icons.person_outline, size: 30)
                                : null,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        session.displayName.isEmpty
                            ? (session.email ?? 'ChargeMY user')
                            : session.displayName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Edit display name',
                      onPressed: () => _showDisplayNameEditor(context, ref),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ],
                ),
              ),
            ),
          if (session.isAdmin)
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text('Administrator account'),
                subtitle: const Text(
                  'Manage stations, users, tickets, and reports.',
                ),
                trailing: FilledButton.icon(
                  onPressed: () => context.go('/admin'),
                  icon: const Icon(Icons.dashboard_outlined),
                  label: const Text('Dashboard'),
                ),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vehicle.displayName,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children:
                        vehicle.connectorTypes
                            .map((item) => Chip(label: Text(item)))
                            .toList(),
                  ),
                  const Divider(height: 28),
                  _Metric(
                    label: 'Battery capacity',
                    value: '${vehicle.batteryKwh.toStringAsFixed(1)} kWh',
                  ),
                  _Metric(
                    label: 'Range',
                    value: '${vehicle.rangeKm.toStringAsFixed(0)} km',
                  ),
                  _Metric(
                    label: 'Charging target',
                    value: '${vehicle.targetSoc}%',
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed:
                        session.isAuthenticated
                            ? () => _showVehicleEditor(context, vehicle)
                            : () => context.push('/auth'),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit and save EV profile'),
                  ),
                ],
              ),
            ),
          ),
          if (session.isAuthenticated)
            Card(
              child: ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('Charging history and e-invoices'),
                subtitle: const Text(
                  'View completed sessions and payment receipts.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/profile/history'),
              ),
            ),
          if (session.isAuthenticated)
            Card(
              child: ListTile(
                leading: const Icon(Icons.confirmation_number_outlined),
                title: const Text('My vouchers'),
                subtitle: const Text('View vouchers or claim a new code.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/profile/vouchers'),
              ),
            ),
          if (session.isAuthenticated)
            Card(
              child: ListTile(
                leading: const Icon(Icons.stars_outlined),
                title: const Text('My rewards'),
                subtitle: const Text(
                  'View your points and redeem charging vouchers.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/profile/rewards'),
              ),
            ),
          if (session.isAuthenticated)
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: const Text('Change password'),
                    subtitle: const Text(
                      'Verify this email with a 6-digit OTP first.',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showPasswordEditor(context, ref),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          Card(
            child: ListTile(
              leading: const Icon(Icons.home_outlined),
              title: const Text('Home location'),
              subtitle: Text(
                _placeSubtitle(session.home, 'Set for nearby-station alerts'),
              ),
              trailing: const Icon(Icons.edit_location_alt_outlined),
              onTap:
                  session.isAuthenticated
                      ? () => _showPlaceEditor(
                        context,
                        isHome: true,
                        place: session.home,
                      )
                      : () => context.push('/auth'),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.business_outlined),
              title: const Text('Work location'),
              subtitle: Text(
                _placeSubtitle(session.work, 'Set for new-station alerts'),
              ),
              trailing: const Icon(Icons.edit_location_alt_outlined),
              onTap:
                  session.isAuthenticated
                      ? () => _showPlaceEditor(
                        context,
                        isHome: false,
                        place: session.work,
                      )
                      : () => context.push('/auth'),
            ),
          ),
          if (session.isAuthenticated)
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: stations.when(
                  loading:
                      () => const ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.favorite_border),
                        title: Text('Favourite stations'),
                        subtitle: Text('Loading your saved stations...'),
                      ),
                  error:
                      (_, _) => const ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.favorite_border),
                        title: Text('Favourite stations'),
                        subtitle: Text('Could not load favourites right now.'),
                      ),
                  data: (items) {
                    final favourites =
                        items.where((item) => item.isFavourite).toList();
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor:
                            Theme.of(context).colorScheme.secondaryContainer,
                        child: Icon(
                          Icons.favorite_border,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      title: const Text('Favourite stations'),
                      subtitle: Text(
                        favourites.isEmpty
                            ? 'Save stations from the map for quick access.'
                            : '${favourites.length} saved station${favourites.length == 1 ? '' : 's'}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showFavouriteStations(context, favourites),
                    );
                  },
                ),
              ),
            ),
          if (session.isAuthenticated)
            Card(
              child: ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Privacy and account'),
                subtitle: const Text(
                  'Manage your account data or delete your account.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showPrivacyDialog(context, ref),
              ),
            ),
          if (session.isAuthenticated)
            TextButton(
              onPressed: () async {
                await ref.read(sessionProvider).signOut();
                if (context.mounted) context.go('/home');
              },
              child: const Text('Sign out'),
            ),
        ],
      ),
    );
  }

  void _showVehicleEditor(BuildContext context, VehicleProfile vehicle) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _VehicleEditorSheet(vehicle: vehicle),
    );
  }

  void _showPlaceEditor(
    BuildContext context, {
    required bool isHome,
    required GeoLocation? place,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PlaceEditorSheet(isHome: isHome, place: place),
    );
  }

  Future<void> _pickAvatar(BuildContext context, WidgetRef ref) async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 1200,
    );
    if (image == null) return;
    try {
      await ref
          .read(sessionProvider)
          .uploadAvatar(await image.readAsBytes(), image.name);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile picture updated.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not upload profile picture. Please try again.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _showDisplayNameEditor(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final value = await showDialog<String>(
      context: context,
      builder:
          (_) => _DisplayNameDialog(
            initialValue: ref.read(sessionProvider).displayName,
          ),
    );
    if (value == null || !context.mounted) return;
    try {
      await ref.read(sessionProvider).updateDisplayName(value);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
      }
    }
  }

  void _showPasswordEditor(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (_) => const _PasswordEditorDialog(),
    );
  }

  static String _placeSubtitle(GeoLocation? place, String empty) {
    if (place == null) return empty;
    return place.address?.isNotEmpty == true ? place.address! : empty;
  }

  Future<void> _showPrivacyDialog(BuildContext context, WidgetRef ref) async {
    final delete = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Privacy and account'),
            content: const Text(
              'ChargeMY stores your EV profile, favourites, saved home/work addresses, hazard reports and charging payment history.\n\nDeleting your account permanently removes your profile and personal data.',
            ),
            actions: [
              TextButton(
                onPressed:
                    () => Navigator.of(
                      dialogContext,
                      rootNavigator: true,
                    ).pop(false),
                child: const Text('Close'),
              ),
              FilledButton.tonal(
                onPressed:
                    () => Navigator.of(
                      dialogContext,
                      rootNavigator: true,
                    ).pop(true),
                child: const Text('Delete account'),
              ),
            ],
          ),
    );
    if (delete != true || !context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Delete account permanently?'),
            content: const Text(
              'This cannot be undone. Continue only if you want to remove your ChargeMY account.',
            ),
            actions: [
              TextButton(
                onPressed:
                    () => Navigator.of(
                      dialogContext,
                      rootNavigator: true,
                    ).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed:
                    () => Navigator.of(
                      dialogContext,
                      rootNavigator: true,
                    ).pop(true),
                child: const Text('Delete permanently'),
              ),
            ],
          ),
    );
    if (confirmed != true || !context.mounted) return;
    final verified = await _verifyEmailForDeletion(context, ref);
    if (!verified || !context.mounted) return;
    try {
      await ref.read(stationRepositoryProvider).deleteMyAccount();
      await ref.read(sessionProvider).signOut();
      if (context.mounted) context.go('/home');
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not delete the account. Please try again.'),
          ),
        );
      }
    }
  }

  Future<bool> _verifyEmailForDeletion(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final session = ref.read(sessionProvider);
    final email = session.email;
    if (email == null || email.isEmpty) return false;
    try {
      await session.sendEmailOtp(email, shouldCreateUser: false);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not send the verification code. Please try again.',
            ),
          ),
        );
      }
      return false;
    }
    if (!context.mounted) return false;
    final code = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _EmailVerificationDialog(email: email),
    );
    if (code == null || code.trim().length != 6 || !context.mounted) {
      return false;
    }
    try {
      await session.verifyEmailOtp(email, code);
      return true;
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The verification code is incorrect. Account was not deleted.',
            ),
          ),
        );
      }
      return false;
    }
  }

  void _showFavouriteStations(
    BuildContext context,
    List<ChargingStation> favourites,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder:
          (sheetContext) => _FavouriteStationsSheet(favourites: favourites),
    );
  }
}

class _FavouriteStationsSheet extends StatelessWidget {
  const _FavouriteStationsSheet({required this.favourites});

  final List<ChargingStation> favourites;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .76,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Favourite stations',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              favourites.isEmpty
                  ? 'Stations you save from the map will appear here.'
                  : '${favourites.length} saved station${favourites.length == 1 ? '' : 's'}',
            ),
            const SizedBox(height: 16),
            Expanded(
              child:
                  favourites.isEmpty
                      ? const AppStateMessage(
                        icon: Icons.favorite_border,
                        title: 'No favourites yet',
                        message:
                            'Tap the heart on a station from the map to save it here.',
                      )
                      : ListView.separated(
                        itemCount: favourites.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final station = favourites[index];
                          return Card(
                            child: ListTile(
                              leading: const Icon(Icons.ev_station_outlined),
                              title: Text(station.name),
                              subtitle: Text(
                                '${station.availableCount} available pile(s) · ${station.address}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          );
                        },
                      ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.go('/home?view=user');
                },
                icon: const Icon(Icons.map_outlined),
                label: const Text('View stations on map'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _EmailVerificationDialog extends StatefulWidget {
  const _EmailVerificationDialog({required this.email});

  final String email;

  @override
  State<_EmailVerificationDialog> createState() =>
      _EmailVerificationDialogState();
}

class _EmailVerificationDialogState extends State<_EmailVerificationDialog> {
  final codeController = TextEditingController();

  @override
  void dispose() {
    codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Verify your email'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Enter the 6-digit code sent to ${widget.email} before deleting your account.',
        ),
        const SizedBox(height: 14),
        TextField(
          controller: codeController,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: '6-digit code',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed:
            () => Navigator.of(
              context,
              rootNavigator: true,
            ).pop(codeController.text),
        child: const Text('Verify'),
      ),
    ],
  );
}

class _DisplayNameDialog extends StatefulWidget {
  const _DisplayNameDialog({required this.initialValue});

  final String initialValue;

  @override
  State<_DisplayNameDialog> createState() => _DisplayNameDialogState();
}

class _DisplayNameDialogState extends State<_DisplayNameDialog> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Display name'),
    content: TextField(
      controller: controller,
      textCapitalization: TextCapitalization.words,
      autofocus: true,
      decoration: const InputDecoration(
        labelText: 'Name shown in ChargeMY',
        border: OutlineInputBorder(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, controller.text),
        child: const Text('Save'),
      ),
    ],
  );
}

class _PlaceEditorSheet extends ConsumerStatefulWidget {
  const _PlaceEditorSheet({required this.isHome, required this.place});
  final bool isHome;
  final GeoLocation? place;

  @override
  ConsumerState<_PlaceEditorSheet> createState() => _PlaceEditorSheetState();
}

class _PlaceEditorSheetState extends ConsumerState<_PlaceEditorSheet> {
  late final TextEditingController address;
  double? selectedLatitude;
  double? selectedLongitude;
  Timer? suggestionTimer;
  List<Map<String, dynamic>> suggestions = const [];
  bool searchingSuggestions = false;
  bool suppressAddressListener = false;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    address = TextEditingController(text: widget.place?.address ?? '');
    address.addListener(_onAddressChanged);
    selectedLatitude = widget.place?.latitude;
    selectedLongitude = widget.place?.longitude;
  }

  @override
  void dispose() {
    address.removeListener(_onAddressChanged);
    suggestionTimer?.cancel();
    address.dispose();
    super.dispose();
  }

  void _onAddressChanged() {
    if (suppressAddressListener) return;
    selectedLatitude = null;
    selectedLongitude = null;
    suggestionTimer?.cancel();
    final query = address.text.trim();
    if (query.length < 2) {
      if (mounted) {
        setState(() {
          suggestions = const [];
          searchingSuggestions = false;
        });
      }
      return;
    }
    suggestionTimer = Timer(
      const Duration(milliseconds: 350),
      () => _fetchSuggestions(query),
    );
  }

  Future<void> _fetchSuggestions(String query) async {
    if (!mounted) return;
    setState(() => searchingSuggestions = true);
    try {
      final results = await _geocode(query, limit: 5);
      if (!mounted || address.text.trim() != query) return;
      setState(() => suggestions = results);
    } catch (_) {
      if (mounted && address.text.trim() == query) {
        setState(() => suggestions = const []);
      }
    } finally {
      if (mounted && address.text.trim() == query) {
        setState(() => searchingSuggestions = false);
      }
    }
  }

  Future<List<Map<String, dynamic>>> _geocode(
    String query, {
    required int limit,
  }) async {
    final response = await http.get(
      Uri.https('nominatim.openstreetmap.org', '/search', {
        'format': 'jsonv2',
        'q': query,
        'countrycodes': 'my',
        'limit': '$limit',
        'addressdetails': '1',
      }),
      headers: const {'User-Agent': 'ChargeMY/1.0 student prototype'},
    );
    if (response.statusCode != 200) throw StateError('Address search failed.');
    return (jsonDecode(response.body) as List)
        .whereType<Map>()
        .map(
          (item) => <String, dynamic>{
            'label': item['display_name'] as String? ?? query,
            'lat': double.tryParse('${item['lat']}'),
            'lng': double.tryParse('${item['lon']}'),
          },
        )
        .where((item) => item['lat'] != null && item['lng'] != null)
        .toList();
  }

  void _selectSuggestion(Map<String, dynamic> result) {
    suppressAddressListener = true;
    address.text = result['label'] as String;
    suppressAddressListener = false;
    setState(() {
      selectedLatitude = result['lat'] as double;
      selectedLongitude = result['lng'] as double;
      suggestions = const [];
    });
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Save ${widget.isHome ? 'home' : 'work'} location',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text('Search and save an exact address privately.'),
            const SizedBox(height: 16),
            TextField(
              controller: address,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Exact address',
                hintText: 'Example: 1 Jalan Ampang, Kuala Lumpur',
                border: OutlineInputBorder(),
              ),
            ),
            if (searchingSuggestions)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (suggestions.isNotEmpty)
              Card(
                margin: const EdgeInsets.only(top: 8),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children:
                      suggestions
                          .map(
                            (result) => ListTile(
                              dense: true,
                              leading: const Icon(Icons.location_on_outlined),
                              title: Text(
                                result['label'] as String,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => _selectSuggestion(result),
                            ),
                          )
                          .toList(),
                ),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: saving ? null : _useCurrentLocation,
              icon: const Icon(Icons.my_location_outlined),
              label: const Text('Use current device location'),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(saving ? 'Saving...' : 'Save location'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _useCurrentLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError('Location permission was not granted.');
      }
      final position = await Geolocator.getCurrentPosition();
      String resolvedAddress = address.text.trim();
      try {
        final response = await http.get(
          Uri.https('nominatim.openstreetmap.org', '/reverse', {
            'format': 'jsonv2',
            'lat': '${position.latitude}',
            'lon': '${position.longitude}',
          }),
          headers: const {'User-Agent': 'ChargeMY/1.0 student prototype'},
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map;
          resolvedAddress = data['display_name'] as String? ?? resolvedAddress;
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        address.text = resolvedAddress;
        selectedLatitude = position.latitude;
        selectedLongitude = position.longitude;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
      }
    }
  }

  Future<void> _save() async {
    if (address.text.trim().isEmpty ||
        selectedLatitude == null ||
        selectedLongitude == null ||
        selectedLatitude!.abs() > 90 ||
        selectedLongitude!.abs() > 180) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Search and choose an exact address on the map first.'),
        ),
      );
      return;
    }
    setState(() => saving = true);
    try {
      await ref
          .read(sessionProvider)
          .savePlace(
            isHome: widget.isHome,
            location: GeoLocation(
              selectedLatitude!,
              selectedLongitude!,
              address: address.text.trim(),
            ),
          );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Saved to your profile.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

class _PasswordEditorDialog extends ConsumerStatefulWidget {
  const _PasswordEditorDialog();

  @override
  ConsumerState<_PasswordEditorDialog> createState() =>
      _PasswordEditorDialogState();
}

class _PasswordEditorDialogState extends ConsumerState<_PasswordEditorDialog> {
  final password = TextEditingController();
  final confirm = TextEditingController();
  final code = TextEditingController();
  bool sent = false;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    password.dispose();
    confirm.dispose();
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change password'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!sent) ...[
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirm,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm new password',
                  border: OutlineInputBorder(),
                ),
              ),
            ] else ...[
              const Text('Enter the 6-digit code sent to your email.'),
              const SizedBox(height: 12),
              TextField(
                controller: code,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: '6-digit code',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: busy ? null : _submit,
          child: Text(
            busy
                ? 'Please wait...'
                : sent
                ? 'Verify & save'
                : 'Verify email',
          ),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final session = ref.read(sessionProvider);
    final email = session.email;
    if (email == null || email.isEmpty) return;
    if (!sent) {
      if (password.text.length < 6) {
        setState(() => error = 'Use at least 6 characters.');
        return;
      }
      if (password.text != confirm.text) {
        setState(() => error = 'Passwords do not match.');
        return;
      }
    } else if (code.text.trim().length != 6) {
      setState(() => error = 'Enter the 6-digit code.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (!sent) {
        await session.sendEmailOtp(email, shouldCreateUser: false);
        setState(() => sent = true);
      } else {
        await session.verifyEmailOtp(email, code.text);
        await session.setPassword(password.text);
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Password updated successfully.')),
          );
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class _VehicleEditorSheet extends ConsumerStatefulWidget {
  const _VehicleEditorSheet({required this.vehicle});

  final VehicleProfile vehicle;

  @override
  ConsumerState<_VehicleEditorSheet> createState() =>
      _VehicleEditorSheetState();
}

class _VehicleEditorSheetState extends ConsumerState<_VehicleEditorSheet> {
  late String brand;
  late _EvCatalogEntry selected;
  late int targetSoc;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final matching = _evCatalog.where(
      (entry) =>
          entry.brand == widget.vehicle.make &&
          entry.model == widget.vehicle.model,
    );
    selected = matching.isNotEmpty ? matching.first : _evCatalog.first;
    brand = selected.brand;
    targetSoc = widget.vehicle.targetSoc;
  }

  List<_EvCatalogEntry> get brandModels =>
      _evCatalog.where((entry) => entry.brand == brand).toList();

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Edit EV profile',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose your vehicle. Battery, range and connectors are fixed from the catalog.',
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: brand,
              decoration: const InputDecoration(
                labelText: 'Vehicle brand',
                border: OutlineInputBorder(),
              ),
              items:
                  const ['Proton', 'Tesla', 'Peugeot']
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  brand = value;
                  selected = brandModels.first;
                });
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: selected.model,
              decoration: const InputDecoration(
                labelText: 'Vehicle model',
                border: OutlineInputBorder(),
              ),
              items:
                  brandModels
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.model,
                          child: Text(entry.model),
                        ),
                      )
                      .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(
                  () =>
                      selected = brandModels.firstWhere(
                        (entry) => entry.model == value,
                      ),
                );
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _fixedMetric(
                    'Battery',
                    '${selected.batteryKwh.toStringAsFixed(1)} kWh',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _fixedMetric(
                    'Range',
                    '${selected.rangeKm.toStringAsFixed(0)} km',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text('Supported connectors'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children:
                  selected.connectors
                      .map((connector) => Chip(label: Text(connector)))
                      .toList(),
            ),
            const SizedBox(height: 12),
            _socField(
              label: 'Default charging target (%)',
              value: targetSoc,
              onChanged: (value) => setState(() => targetSoc = value),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(saving ? 'Saving...' : 'Save vehicle profile'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _fixedMetric(String label, String value) => InputDecorator(
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      filled: true,
      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
    ),
    child: Text(value),
  );

  Widget _socField({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) => TextFormField(
    initialValue: '$value',
    keyboardType: TextInputType.number,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    onChanged: (text) {
      final parsed = int.tryParse(text);
      if (parsed != null) onChanged(parsed);
    },
  );

  Future<void> _save() async {
    if (targetSoc < 20 || targetSoc > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Target must be within 20-100%.')),
      );
      return;
    }
    setState(() => saving = true);
    try {
      final id = '${selected.brand}-${selected.model}'.toLowerCase().replaceAll(
        RegExp('[^a-z0-9]+'),
        '-',
      );
      await ref
          .read(sessionProvider)
          .saveVehicle(
            VehicleProfile(
              id: id,
              make: selected.brand,
              model: selected.model,
              batteryKwh: selected.batteryKwh,
              efficiencyWhPerKm: selected.batteryKwh * 1000 / selected.rangeKm,
              connectorTypes: selected.connectors,
              targetSoc: targetSoc,
              reserveSoc: widget.vehicle.reserveSoc,
            ),
          );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vehicle profile saved securely.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Text(label),
        const Spacer(),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    ),
  );
}
