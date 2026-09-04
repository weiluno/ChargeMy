import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../domain/models/charging_models.dart';
import '../../../domain/services/open_route_service.dart';
import '../../../services/local_notification_service.dart';
import '../../../services/stripe_payment_service.dart';
import '../../core/app_state.dart';
import '../../core/map_tiles.dart';
import '../../core/widgets.dart';
import '../navigation/in_app_navigation_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool compatibleOnly = false;
  bool availableOnly = false;
  String? selectedConnector;
  String? selectedBrand;
  String? selectedEnvironment;
  double? maximumPrice;
  GeoLocation? _currentLocation;
  bool _searchOpen = false;
  bool _showScrollToTop = false;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _homeScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _homeScrollController.addListener(_onHomeScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _useCurrentLocation(showFeedback: false);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _homeScrollController.removeListener(_onHomeScroll);
    _homeScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stations = ref.watch(stationsProvider);
    final vehicle = ref.watch(sessionProvider.select((s) => s.vehicle));
    final isAdmin = ref.watch(sessionProvider.select((s) => s.isAdmin));
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ChargeMY'),
            Text(
              'Malaysia EV charging navigator',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          if (isAdmin)
            IconButton(
              tooltip: 'Admin dashboard',
              onPressed: () => context.go('/admin'),
              icon: const Icon(Icons.dashboard_outlined),
            ),
          IconButton(
            tooltip: 'Plan a journey',
            onPressed: () => _startTripRoute(context),
            icon: const Icon(Icons.alt_route_rounded),
          ),
          IconButton(
            tooltip: 'Profile',
            onPressed: () => context.push('/profile'),
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
      body: stations.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:
            (error, _) => _StationLoadError(
              onRetry: () => ref.invalidate(stationsProvider),
            ),
        data: (items) {
          final visible =
              items.where((station) {
                final connectorMatch =
                    selectedConnector == null ||
                    station.connectorTypes.contains(selectedConnector);
                final vehicleMatch =
                    !compatibleOnly ||
                    station.connectorTypes.any(vehicle.connectorTypes.contains);
                final availableMatch =
                    !availableOnly || station.availableCount > 0;
                final brandMatch =
                    selectedBrand == null || station.brand == selectedBrand;
                final environmentMatch =
                    selectedEnvironment == null ||
                    station.indoorOutdoor == selectedEnvironment;
                final priceMatch =
                    maximumPrice == null ||
                    station.lowestPrice <= maximumPrice!;
                final searchValue = _searchController.text.trim().toLowerCase();
                final searchMatch =
                    searchValue.isEmpty ||
                    cleanDisplayText(
                      station.name,
                    ).toLowerCase().contains(searchValue) ||
                    cleanDisplayText(
                      station.address,
                    ).toLowerCase().contains(searchValue) ||
                    cleanDisplayText(
                      station.brand,
                    ).toLowerCase().contains(searchValue);
                return connectorMatch &&
                    vehicleMatch &&
                    availableMatch &&
                    brandMatch &&
                    environmentMatch &&
                    priceMatch &&
                    searchMatch;
              }).toList();
          visible.sort((left, right) {
            if (left.isFavourite != right.isFavourite) {
              return left.isFavourite ? -1 : 1;
            }
            if (_currentLocation == null) {
              return left.name.compareTo(right.name);
            }
            return _distanceKm(
              left.location,
              _currentLocation!,
            ).compareTo(_distanceKm(right.location, _currentLocation!));
          });
          return Stack(
            children: [
              CustomScrollView(
                key: const PageStorageKey<String>('chargemy-home-scroll'),
                controller: _homeScrollController,
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                      child: _FilterBar(
                        compatibleOnly: compatibleOnly,
                        selectedConnector: selectedConnector,
                        onCompatibleChanged:
                            (value) => setState(() => compatibleOnly = value),
                        onConnectorChanged:
                            (value) =>
                                setState(() => selectedConnector = value),
                        availableOnly: availableOnly,
                        onAvailableChanged:
                            (value) => setState(() => availableOnly = value),
                        onMoreFilters: () => _showMoreFilters(context, items),
                        onSearch:
                            () => setState(() => _searchOpen = !_searchOpen),
                      ),
                    ),
                  ),
                  if (_searchOpen)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                        child: TextField(
                          controller: _searchController,
                          autofocus: true,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Search stations',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: IconButton(
                              tooltip: 'Close search',
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchOpen = false);
                              },
                              icon: const Icon(Icons.close),
                            ),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ),
                  if (_hasActiveFilters)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _activeFilterText,
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                            ),
                            TextButton(
                              onPressed: _clearFilters,
                              child: const Text('Clear filters'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: _ActiveChargingSection()),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _MapPreview(
                        stations: visible,
                        currentLocation: _currentLocation,
                        onSelect: _showStation,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                      child: SectionTitle(
                        title:
                            _currentLocation == null
                                ? '${visible.length} stations'
                                : '${visible.length} nearby stations',
                        action: Text(
                          _currentLocation == null
                              ? 'Tap location for distance'
                              : '${vehicle.displayName} matched',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                    ),
                  ),
                  SliverList.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder:
                        (context, index) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _StationCard(
                            station: visible[index],
                            origin: _currentLocation,
                            onTap: () => _showStation(visible[index]),
                          ),
                        ),
                  ),
                  if (visible.isEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(32, 12, 32, 24),
                        child: Text(
                          'No stations match these filters. Tap the selected filter again to clear it.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 32)),
                ],
              ),
              Positioned(
                right: 20,
                bottom: 20,
                child: SafeArea(
                  top: false,
                  child: IgnorePointer(
                    ignoring: !_showScrollToTop,
                    child: AnimatedSlide(
                      duration: const Duration(milliseconds: 180),
                      offset:
                          _showScrollToTop ? Offset.zero : const Offset(0, 1),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 180),
                        opacity: _showScrollToTop ? 1 : 0,
                        child: FloatingActionButton.small(
                          tooltip: 'Back to top',
                          onPressed: _scrollToTop,
                          child: const Icon(Icons.vertical_align_top_rounded),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _onHomeScroll() {
    if (!_homeScrollController.hasClients) return;
    final shouldShow = _homeScrollController.offset > 420;
    if (shouldShow == _showScrollToTop || !mounted) return;
    setState(() => _showScrollToTop = shouldShow);
  }

  void _scrollToTop() {
    if (!_homeScrollController.hasClients) return;
    _homeScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  void _showStation(ChargingStation station) {
    final origin = _currentLocation;
    if (origin != null) {
      unawaited(
        OpenRouteService.drivingRoute(
          origin: origin,
          destination: station.location,
        ),
      );
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder:
          (_) => _StationInspector(
            station: station,
            currentLocation: _currentLocation,
          ),
    );
  }

  Future<void> _useCurrentLocation({bool showFeedback = true}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError('Turn on Location on the emulator/device first.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError('Location permission was not granted.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (mounted) {
        setState(
          () =>
              _currentLocation = GeoLocation(
                position.latitude,
                position.longitude,
              ),
        );
        if (showFeedback) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Using device location: ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}',
              ),
            ),
          );
        }
      }
    } catch (error) {
      if (mounted && showFeedback) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
      }
    }
  }

  double _distanceKm(GeoLocation first, GeoLocation second) =>
      Geolocator.distanceBetween(
        first.latitude,
        first.longitude,
        second.latitude,
        second.longitude,
      ) /
      1000;

  void _showMoreFilters(BuildContext context, List<ChargingStation> stations) {
    final brands =
        stations.map((station) => station.brand).toSet().toList()..sort();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder:
          (_) => _MoreFiltersSheet(
            brands: brands,
            selectedBrand: selectedBrand,
            selectedEnvironment: selectedEnvironment,
            maximumPrice: maximumPrice,
            onApply: (brand, environment, price) {
              setState(() {
                selectedBrand = brand;
                selectedEnvironment = environment;
                maximumPrice = price;
              });
            },
          ),
    );
  }

  bool get _hasActiveFilters =>
      compatibleOnly ||
      availableOnly ||
      selectedConnector != null ||
      selectedBrand != null ||
      selectedEnvironment != null ||
      maximumPrice != null;

  String get _activeFilterText {
    final filters = <String>[
      if (compatibleOnly) 'My vehicle',
      if (availableOnly) 'Available',
      if (selectedConnector != null) selectedConnector!,
      if (selectedBrand != null) selectedBrand!,
      if (selectedEnvironment != null) selectedEnvironment!,
      if (maximumPrice != null) '≤ RM ${maximumPrice!.toStringAsFixed(2)}',
    ];
    return 'Filters: ${filters.join(' · ')}';
  }

  void _clearFilters() {
    setState(() {
      compatibleOnly = false;
      availableOnly = false;
      selectedConnector = null;
      selectedBrand = null;
      selectedEnvironment = null;
      maximumPrice = null;
    });
  }

  Future<void> _startTripRoute(BuildContext context) async {
    final user = ref.read(sessionProvider);
    if (user.activeSession != null) {
      await showDialog<void>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: const Text('Charging still in progress'),
              content: const Text(
                'Please unplug and complete your current charging session before routing to another station.',
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('OK'),
                ),
              ],
            ),
      );
      return;
    }
    if (context.mounted) context.push('/trip');
  }
}

class _ActiveChargingSection extends ConsumerWidget {
  const _ActiveChargingSection();

  Future<void> _stopCharging(BuildContext context, WidgetRef ref) async {
    final approved = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Stop charging?'),
            content: const Text(
              'Stop the session and pay for the energy used so far? The pile will be released after payment.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Keep charging'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Stop and pay'),
              ),
            ],
          ),
    );
    if (approved == true && context.mounted) {
      await _payAndComplete(context, ref);
    }
  }

  Future<void> _completeCharging(BuildContext context, WidgetRef ref) async {
    await _payAndComplete(context, ref);
  }

  Future<void> _payAndComplete(BuildContext context, WidgetRef ref) async {
    final latest = ref.read(sessionProvider).activeSession;
    if (latest == null) return;
    final startSoc =
        latest.startSoc ?? (latest.stateOfCharge ?? 0).clamp(0, 100).toInt();
    final reportedSoc = (latest.stateOfCharge ?? startSoc).toDouble();
    final elapsedSoc =
        latest.startedAt != null &&
                latest.batteryKwh != null &&
                latest.chargePowerKw != null
            ? socAfterChargingPrecise(
              batteryKwh: latest.batteryKwh!,
              stationPowerKw: latest.chargePowerKw!,
              startSoc: startSoc,
              targetSoc: latest.effectiveTargetSoc,
              elapsed: DateTime.now().difference(latest.startedAt!),
            )
            : reportedSoc;
    final currentSoc =
        math
            .max(reportedSoc, elapsedSoc)
            .clamp(startSoc, latest.effectiveTargetSoc)
            .floor();
    final energyKwh =
        (((latest.batteryKwh ?? ref.read(sessionProvider).vehicle.batteryKwh) *
                        ((currentSoc - startSoc).clamp(0, 100) / 100))
                    .toDouble() *
                100)
            .roundToDouble() /
        100;
    final amount =
        (math.max(2.0, energyKwh * 1.20) * 100).roundToDouble() / 100;

    List<Voucher> vouchers = const <Voucher>[];
    try {
      vouchers = await ref.read(stationRepositoryProvider).loadMyVouchers();
    } catch (_) {}
    if (!context.mounted) return;
    final paymentChoice = await showDialog<_PaymentChoice>(
      context: context,
      builder:
          (_) => _PaymentChoiceDialog(
            energyKwh: energyKwh,
            amountMyr: amount,
            vouchers: vouchers,
          ),
    );
    if (paymentChoice == null || !context.mounted) return;

    try {
      final checkout = await StripePaymentService.payChargingSession(
        amountMyr: amount,
        sessionId: latest.id,
        stationId: latest.stationId,
        voucherClaimId: paymentChoice.voucher?.claimId,
      );
      await ref
          .read(stationRepositoryProvider)
          .completeCharge(latest.id, energyKwh: energyKwh, endSoc: currentSoc);
      final receiptEmail = ref.read(sessionProvider).email;
      var pointsEarned = 0;
      try {
        pointsEarned = await ref
            .read(stationRepositoryProvider)
            .recordChargingPayment(
              sessionId: latest.id,
              amountMyr: checkout.finalAmountMyr,
              energyKwh: energyKwh,
              receiptEmail: receiptEmail,
              voucherClaimId: checkout.voucherClaimId,
              originalAmountMyr: checkout.originalAmountMyr,
            );
      } catch (_) {}
      var receiptSent = false;
      var receiptReason = 'unknown';
      try {
        final receipt = await Supabase.instance.client.functions.invoke(
          'send-payment-receipt',
          body: {
            'amountMyr': checkout.finalAmountMyr,
            'originalAmountMyr': checkout.originalAmountMyr,
            'discountMyr': checkout.discountMyr,
            'voucherCode':
                paymentChoice.voucher?.isRewardVoucher == true
                    ? paymentChoice.voucher!.title
                    : paymentChoice.voucher?.code,
            'energyKwh': energyKwh,
            'endSoc': currentSoc,
            'sessionId': latest.id,
            'stationId': latest.stationId,
          },
        );
        if (receipt.data is Map) {
          receiptSent = receipt.data['sent'] == true;
          receiptReason = receipt.data['reason']?.toString() ?? receiptReason;
        }
      } catch (_) {}
      ref.read(sessionProvider).clearActiveSession();
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder:
              (dialogContext) => Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: Colors.green.shade100,
                        child: Icon(
                          Icons.check_rounded,
                          size: 38,
                          color: Colors.green.shade800,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Payment successful',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color:
                              Theme.of(
                                dialogContext,
                              ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          children: [
                            _PaymentSummaryRow(
                              label: 'Charging total',
                              value:
                                  'RM ${checkout.originalAmountMyr.toStringAsFixed(2)}',
                            ),
                            if (checkout.discountMyr > 0) ...[
                              const SizedBox(height: 10),
                              _PaymentSummaryRow(
                                label: 'Voucher used',
                                value:
                                    paymentChoice.voucher?.isRewardVoucher ==
                                            true
                                        ? paymentChoice.voucher!.title
                                        : paymentChoice.voucher?.code ??
                                            'Voucher',
                              ),
                              const SizedBox(height: 10),
                              _PaymentSummaryRow(
                                label: 'Voucher discount',
                                value:
                                    '- RM ${checkout.discountMyr.toStringAsFixed(2)}',
                              ),
                            ],
                            const Divider(height: 24),
                            _PaymentSummaryRow(
                              label: 'Amount paid',
                              value:
                                  'RM ${checkout.finalAmountMyr.toStringAsFixed(2)}',
                              emphasize: true,
                            ),
                            if (pointsEarned > 0) ...[
                              const SizedBox(height: 10),
                              _PaymentSummaryRow(
                                label: 'Points earned',
                                value: '+$pointsEarned points',
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text('${energyKwh.toStringAsFixed(2)} kWh charged'),
                      const SizedBox(height: 16),
                      Text(
                        receiptSent && receiptEmail != null
                            ? 'E-invoice has been sent to your email.'
                            : receiptReason == 'not_configured'
                            ? 'Payment is complete. Email receipts are not configured yet.'
                            : 'Payment is complete. The receipt email could not be sent.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color:
                              Theme.of(
                                dialogContext,
                              ).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Done'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              friendlyErrorMessage(
                error,
                fallback: 'Payment could not be completed. Please try again.',
              ),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasActive = ref.watch(
      sessionProvider.select((s) => s.activeSession != null),
    );
    if (!hasActive) return const SizedBox.shrink();
    final active = ref.read(sessionProvider).activeSession!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: _ActiveChargingBanner(
        session: active,
        targetSoc: active.effectiveTargetSoc,
        onStop: () => _stopCharging(context, ref),
        onComplete: () => _completeCharging(context, ref),
      ),
    );
  }
}

class _PaymentChoice {
  const _PaymentChoice({this.voucher});

  final Voucher? voucher;
}

class _PaymentChoiceDialog extends StatefulWidget {
  const _PaymentChoiceDialog({
    required this.energyKwh,
    required this.amountMyr,
    required this.vouchers,
  });

  final double energyKwh;
  final double amountMyr;
  final List<Voucher> vouchers;

  @override
  State<_PaymentChoiceDialog> createState() => _PaymentChoiceDialogState();
}

class _PaymentChoiceDialogState extends State<_PaymentChoiceDialog> {
  Voucher? _selectedVoucher;

  String? _voucherUnavailableReason(Voucher voucher) {
    if (voucher.isUsed) return 'Used';
    if (voucher.isExpired) return 'Expired';
    if (!voucher.isActive) return 'Unavailable';
    if (widget.amountMyr + .0001 < voucher.effectiveMinimumSpendMyr) {
      return 'Min RM ${voucher.effectiveMinimumSpendMyr.toStringAsFixed(2)}';
    }
    if (!voucher.canApplyToStripePayment(widget.amountMyr)) {
      return 'Final payment below RM 2.00';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final paymentVouchers =
        widget.vouchers.where((voucher) => voucher.isAvailable).toList();
    final eligible =
        paymentVouchers
            .where(
              (voucher) => voucher.canApplyToStripePayment(widget.amountMyr),
            )
            .toList();
    final discount = _selectedVoucher?.discountFor(widget.amountMyr) ?? 0;
    final total = widget.amountMyr - discount;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(
                Icons.receipt_long_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 30,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Confirm charging payment',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  _PaymentSummaryRow(
                    label: 'Energy used',
                    value: '${widget.energyKwh.toStringAsFixed(2)} kWh',
                  ),
                  const SizedBox(height: 10),
                  _PaymentSummaryRow(
                    label: 'Charging subtotal',
                    value: 'RM ${widget.amountMyr.toStringAsFixed(2)}',
                  ),
                  if (_selectedVoucher != null) ...[
                    const SizedBox(height: 10),
                    _PaymentSummaryRow(
                      label: 'Voucher discount',
                      value: '- RM ${discount.toStringAsFixed(2)}',
                    ),
                  ],
                  const Divider(height: 24),
                  _PaymentSummaryRow(
                    label: 'Amount to pay',
                    value: 'RM ${total.toStringAsFixed(2)}',
                    emphasize: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Optional voucher',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              value: _selectedVoucher?.claimId,
              isExpanded: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.local_offer_outlined),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Do not use a voucher'),
                ),
                for (final voucher in paymentVouchers)
                  DropdownMenuItem<String?>(
                    value: voucher.claimId,
                    enabled: _voucherUnavailableReason(voucher) == null,
                    child: Text(
                      [
                        voucher.isRewardVoucher
                            ? voucher.title
                            : '${voucher.title} (${voucher.code})',
                        voucher.discountLabel,
                        if (_voucherUnavailableReason(voucher)
                            case final reason?)
                          reason,
                      ].join(' · '),
                      overflow: TextOverflow.ellipsis,
                      style:
                          _voucherUnavailableReason(voucher) == null
                              ? null
                              : TextStyle(
                                color: Theme.of(context).disabledColor,
                              ),
                    ),
                  ),
              ],
              onChanged: (claimId) {
                setState(
                  () =>
                      _selectedVoucher =
                          eligible
                              .where((voucher) => voucher.claimId == claimId)
                              .firstOrNull,
                );
              },
            ),
            if (paymentVouchers.any(
              (voucher) => _voucherUnavailableReason(voucher) != null,
            )) ...[
              const SizedBox(height: 8),
              const Text(
                'Grey vouchers cannot be used for this payment. Check the reason shown beside each code.',
                style: TextStyle(fontSize: 12),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed:
                        () => Navigator.pop(
                          context,
                          _PaymentChoice(voucher: _selectedVoucher),
                        ),
                    child: const Text('Continue'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentSummaryRow extends StatelessWidget {
  const _PaymentSummaryRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(
          value,
          style: TextStyle(
            fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
            fontSize: emphasize ? 17 : null,
          ),
        ),
      ],
    );
  }
}

class _ActiveChargingBanner extends StatelessWidget {
  const _ActiveChargingBanner({
    required this.session,
    required this.targetSoc,
    required this.onStop,
    required this.onComplete,
  });

  final ChargingSession session;
  final int targetSoc;
  final VoidCallback onStop;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final target = session.targetSoc ?? targetSoc;
    final start = session.startSoc ?? 0;
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bolt),
                const SizedBox(width: 8),
                const Expanded(child: Text('Charging in progress')),
                _ChargingActionButton(
                  session: session,
                  startSoc: start,
                  targetSoc: target,
                  onStop: onStop,
                  onComplete: onComplete,
                ),
              ],
            ),
            _ChargingLiveStatus(
              session: session,
              startSoc: start,
              targetSoc: target,
            ),
            const Text(
              'Progress updates automatically. The device notification bar also shows the current charge.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChargingActionButton extends StatefulWidget {
  const _ChargingActionButton({
    required this.session,
    required this.startSoc,
    required this.targetSoc,
    required this.onStop,
    required this.onComplete,
  });

  final ChargingSession session;
  final int startSoc;
  final int targetSoc;
  final VoidCallback onStop;
  final VoidCallback onComplete;

  @override
  State<_ChargingActionButton> createState() => _ChargingActionButtonState();
}

class _ChargingActionButtonState extends State<_ChargingActionButton> {
  Timer? _timer;
  bool _reached = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  void _refresh() {
    final startedAt = widget.session.startedAt;
    final batteryKwh = widget.session.batteryKwh;
    final powerKw = widget.session.chargePowerKw;
    final current =
        startedAt != null && batteryKwh != null && powerKw != null
            ? socAfterChargingPrecise(
              batteryKwh: batteryKwh,
              stationPowerKw: powerKw,
              startSoc: widget.startSoc,
              targetSoc: widget.targetSoc,
              elapsed: DateTime.now().difference(startedAt),
            )
            : (widget.session.stateOfCharge ?? widget.startSoc).toDouble();
    final reached = current >= widget.targetSoc;
    if (mounted && reached != _reached) setState(() => _reached = reached);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: _reached ? widget.onComplete : widget.onStop,
    child: Text(_reached ? 'Complete' : 'Stop'),
  );
}

class _ChargingLiveStatus extends StatefulWidget {
  const _ChargingLiveStatus({
    required this.session,
    required this.startSoc,
    required this.targetSoc,
  });

  final ChargingSession session;
  final int startSoc;
  final int targetSoc;

  @override
  State<_ChargingLiveStatus> createState() => _ChargingLiveStatusState();
}

class _ChargingLiveStatusState extends State<_ChargingLiveStatus> {
  Timer? _timer;
  double _preciseSoc = 0;
  int _displayedSoc = 0;
  int? _lastNotifiedSoc;
  Duration? _remaining;

  @override
  void initState() {
    super.initState();
    _updateProgress();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateProgress(),
    );
  }

  @override
  void didUpdateWidget(covariant _ChargingLiveStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.id != widget.session.id ||
        oldWidget.session.stateOfCharge != widget.session.stateOfCharge ||
        oldWidget.session.startedAt != widget.session.startedAt ||
        oldWidget.startSoc != widget.startSoc ||
        oldWidget.targetSoc != widget.targetSoc) {
      _updateProgress();
    }
  }

  void _updateProgress() {
    final session = widget.session;
    final startedAt = session.startedAt;
    final batteryKwh = session.batteryKwh;
    final powerKw = session.chargePowerKw;
    final preciseSoc =
        startedAt != null && batteryKwh != null && powerKw != null
            ? socAfterChargingPrecise(
              batteryKwh: batteryKwh,
              stationPowerKw: powerKw,
              startSoc: widget.startSoc,
              targetSoc: widget.targetSoc,
              elapsed: DateTime.now().difference(startedAt),
            )
            : (session.stateOfCharge ?? widget.startSoc).toDouble();
    final total =
        batteryKwh != null && powerKw != null
            ? estimateChargingDuration(
              batteryKwh: batteryKwh,
              stationPowerKw: powerKw,
              startSoc: widget.startSoc,
              targetSoc: widget.targetSoc,
            )
            : null;
    final elapsed =
        startedAt == null
            ? Duration.zero
            : DateTime.now().difference(startedAt);
    final remaining = total == null ? null : total - elapsed;
    final displayedSoc = preciseSoc.floor().clamp(
      widget.startSoc,
      widget.targetSoc,
    );
    final safeRemaining =
        remaining == null || !remaining.isNegative ? remaining : Duration.zero;
    if (!mounted) return;
    setState(() {
      _preciseSoc = preciseSoc;
      _displayedSoc = displayedSoc;
      _remaining = safeRemaining;
    });
    if (_lastNotifiedSoc != displayedSoc && displayedSoc < widget.targetSoc) {
      _lastNotifiedSoc = displayedSoc;
      unawaited(
        LocalNotificationService.instance.showChargingProgress(
          currentSoc: displayedSoc,
          targetSoc: widget.targetSoc,
          remaining: safeRemaining,
        ),
      );
    }
    if (preciseSoc >= widget.targetSoc) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress =
        widget.targetSoc <= widget.startSoc
            ? 1.0
            : ((_preciseSoc - widget.startSoc) /
                    (widget.targetSoc - widget.startSoc))
                .clamp(0.0, 1.0)
                .toDouble();
    final reached = _displayedSoc >= widget.targetSoc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$_displayedSoc% charged · Target ${widget.targetSoc}%'),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: progress),
        const SizedBox(height: 6),
        if (reached)
          const Text(
            'Target reached. Unplug or complete the session.',
            style: TextStyle(fontSize: 12),
          )
        else if (_remaining != null)
          Text(
            'Estimated time remaining: ${_formatDuration(_remaining!)}',
            style: const TextStyle(fontSize: 12),
          ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    if (duration <= Duration.zero) return '0 min';
    final minutes = (duration.inSeconds / 60).ceil();
    return '$minutes min';
  }
}

class _StationLoadError extends StatelessWidget {
  const _StationLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 44),
          const SizedBox(height: 12),
          Text(
            'Stations could not be loaded.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          const Text(
            'Check the emulator internet connection, then try again.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.compatibleOnly,
    required this.selectedConnector,
    required this.onCompatibleChanged,
    required this.onConnectorChanged,
    required this.availableOnly,
    required this.onAvailableChanged,
    required this.onMoreFilters,
    required this.onSearch,
  });

  final bool compatibleOnly;
  final String? selectedConnector;
  final ValueChanged<bool> onCompatibleChanged;
  final ValueChanged<String?> onConnectorChanged;
  final bool availableOnly;
  final ValueChanged<bool> onAvailableChanged;
  final VoidCallback onMoreFilters;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          FilterChip(
            label: const Text('My vehicle'),
            selected: compatibleOnly,
            onSelected: onCompatibleChanged,
            avatar: const Icon(Icons.electric_car_outlined, size: 18),
          ),
          FilterChip(
            label: const Text('Available now'),
            selected: availableOnly,
            onSelected: onAvailableChanged,
            avatar: const Icon(Icons.bolt_outlined, size: 18),
          ),
          for (final connector in const ['CCS2', 'Type 2', 'CHAdeMO'])
            ChoiceChip(
              label: Text(connector),
              selected: selectedConnector == connector,
              onSelected:
                  (chosen) => onConnectorChanged(chosen ? connector : null),
            ),
          ActionChip(
            avatar: const Icon(Icons.tune_outlined, size: 18),
            label: const Text('More filters'),
            onPressed: onMoreFilters,
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Search stations',
            onPressed: onSearch,
            icon: const Icon(Icons.search),
          ),
        ],
      ),
    );
  }
}

class _MoreFiltersSheet extends StatefulWidget {
  const _MoreFiltersSheet({
    required this.brands,
    required this.selectedBrand,
    required this.selectedEnvironment,
    required this.maximumPrice,
    required this.onApply,
  });

  final List<String> brands;
  final String? selectedBrand;
  final String? selectedEnvironment;
  final double? maximumPrice;
  final void Function(String?, String?, double?) onApply;

  @override
  State<_MoreFiltersSheet> createState() => _MoreFiltersSheetState();
}

class _MoreFiltersSheetState extends State<_MoreFiltersSheet> {
  late String? brand = widget.selectedBrand;
  late String? environment = widget.selectedEnvironment;
  late double? price = widget.maximumPrice;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .72,
    ),
    child: Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        primary: true,
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: 24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('More filters', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              value: brand,
              decoration: const InputDecoration(labelText: 'Charging brand'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Any brand'),
                ),
                ...widget.brands.map(
                  (value) => DropdownMenuItem<String?>(
                    value: value,
                    child: Text(value),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => brand = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              value: environment,
              decoration: const InputDecoration(labelText: 'Location type'),
              items: const [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Indoor or outdoor'),
                ),
                DropdownMenuItem<String?>(
                  value: 'Indoor',
                  child: Text('Indoor'),
                ),
                DropdownMenuItem<String?>(
                  value: 'Outdoor',
                  child: Text('Outdoor'),
                ),
              ],
              onChanged: (value) => setState(() => environment = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<double?>(
              value: price,
              decoration: const InputDecoration(labelText: 'Maximum price'),
              items: const [
                DropdownMenuItem<double?>(
                  value: null,
                  child: Text('Any price'),
                ),
                DropdownMenuItem<double?>(
                  value: 1.00,
                  child: Text('Up to RM 1.00/kWh'),
                ),
                DropdownMenuItem<double?>(
                  value: 1.30,
                  child: Text('Up to RM 1.30/kWh'),
                ),
                DropdownMenuItem<double?>(
                  value: 1.60,
                  child: Text('Up to RM 1.60/kWh'),
                ),
              ],
              onChanged: (value) => setState(() => price = value),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  widget.onApply(brand, environment, price);
                  Navigator.of(context).pop();
                },
                child: const Text('Apply filters'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MapPreview extends StatefulWidget {
  const _MapPreview({
    required this.stations,
    required this.currentLocation,
    required this.onSelect,
  });

  final List<ChargingStation> stations;
  final GeoLocation? currentLocation;
  final ValueChanged<ChargingStation> onSelect;

  @override
  State<_MapPreview> createState() => _MapPreviewState();
}

class _MapPreviewState extends State<_MapPreview> {
  final MapController _mapController = MapController();
  late bool _centeredOnUser;

  @override
  void initState() {
    super.initState();
    _centeredOnUser = widget.currentLocation != null;
  }

  @override
  void didUpdateWidget(covariant _MapPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_centeredOnUser &&
        oldWidget.currentLocation == null &&
        widget.currentLocation != null) {
      _centeredOnUser = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _centerOnUser());
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 300,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter:
                    widget.currentLocation == null
                        ? const LatLng(3.56, 101.35)
                        : LatLng(
                          widget.currentLocation!.latitude,
                          widget.currentLocation!.longitude,
                        ),
                initialZoom: widget.currentLocation == null ? 6.3 : 14.5,
              ),
              children: [
                chargeMyTileLayer(),
                MarkerLayer(
                  markers: [
                    if (widget.currentLocation != null)
                      Marker(
                        point: LatLng(
                          widget.currentLocation!.latitude,
                          widget.currentLocation!.longitude,
                        ),
                        width: 48,
                        height: 48,
                        child: const Icon(
                          Icons.location_on_rounded,
                          color: Color(0xFF1677E8),
                          size: 46,
                          shadows: [
                            Shadow(color: Colors.white, blurRadius: 5),
                            Shadow(color: Colors.black26, blurRadius: 8),
                          ],
                        ),
                      ),
                    ...widget.stations.map(
                      (station) => Marker(
                        point: LatLng(
                          station.location.latitude,
                          station.location.longitude,
                        ),
                        width: 48,
                        height: 48,
                        child: _MapPin(
                          station: station,
                          onTap: () => widget.onSelect(station),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Positioned(left: 18, top: 16, child: _MapLegend()),
            const Positioned(
              left: 12,
              bottom: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.white70),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Text(
                    '© OpenStreetMap contributors',
                    style: TextStyle(fontSize: 10),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 12,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Card(
                    margin: EdgeInsets.zero,
                    child: Column(
                      children: [
                        if (widget.currentLocation != null) ...[
                          IconButton(
                            tooltip: 'Center on my location',
                            onPressed: _centerOnUser,
                            icon: Icon(
                              Icons.my_location,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const Divider(height: 1),
                        ],
                        IconButton(
                          tooltip: 'Zoom in',
                          onPressed: () => _zoomBy(1),
                          icon: const Icon(Icons.add),
                        ),
                        const Divider(height: 1),
                        IconButton(
                          tooltip: 'Zoom out',
                          onPressed: () => _zoomBy(-1),
                          icon: const Icon(Icons.remove),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Chip(
                    avatar: Icon(Icons.zoom_in_map_outlined, size: 17),
                    label: Text('Pinch to explore'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _zoomBy(double delta) {
    final camera = _mapController.camera;
    _mapController.move(
      camera.center,
      (camera.zoom + delta).clamp(3.0, 19.0).toDouble(),
    );
  }

  void _centerOnUser() {
    final location = widget.currentLocation;
    if (location == null) return;
    _mapController.move(LatLng(location.latitude, location.longitude), 14.5);
  }
}

class _MapLegend extends StatelessWidget {
  const _MapLegend();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Padding(
        padding: EdgeInsets.all(9),
        child: Text(
          'Live station status',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
      ),
    );
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin({required this.station, required this.onTap});

  final ChargingStation station;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(station.mapStatus);
    return Semantics(
      button: true,
      label: '${station.name}, ${statusLabel(station.mapStatus)}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
          ),
          child: const Icon(Icons.bolt_rounded, color: Colors.white),
        ),
      ),
    );
  }
}

class _StationCard extends StatelessWidget {
  const _StationCard({
    required this.station,
    required this.origin,
    required this.onTap,
  });

  final ChargingStation station;
  final GeoLocation? origin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: statusColor(
            station.mapStatus,
          ).withValues(alpha: .15),
          child: Icon(
            Icons.ev_station_rounded,
            color: statusColor(station.mapStatus),
          ),
        ),
        title: Text(
          cleanDisplayText(station.name),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        isThreeLine: true,
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${cleanDisplayText(station.brand)} · ${station.lowestPrice.toStringAsFixed(2)} RM/kWh · ${station.availableCount}/${station.piles.length} free',
              ),
              if (origin != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: _RoadDistanceText(
                    origin: origin!,
                    destination: station.location,
                  ),
                ),
            ],
          ),
        ),
        trailing: StatusPill(status: station.mapStatus),
      ),
    );
  }
}

class _RoadDistanceText extends StatelessWidget {
  const _RoadDistanceText({required this.origin, required this.destination});

  final GeoLocation origin;
  final GeoLocation destination;

  @override
  Widget build(BuildContext context) {
    final distanceKm =
        Geolocator.distanceBetween(
          origin.latitude,
          origin.longitude,
          destination.latitude,
          destination.longitude,
        ) /
        1000;
    return Text('${distanceKm.toStringAsFixed(1)} km away');
  }
}

class _StationInspector extends ConsumerWidget {
  const _StationInspector({
    required this.station,
    required this.currentLocation,
  });

  final ChargingStation station;
  final GeoLocation? currentLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .88,
        ),
        child: Scrollbar(
          thumbVisibility: true,
          child: SingleChildScrollView(
            primary: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        cleanDisplayText(station.name),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        if (!user.isAuthenticated) {
                          context.push('/auth');
                          return;
                        }
                        try {
                          await ref
                              .read(stationRepositoryProvider)
                              .toggleFavourite(station.id);
                          ref.invalidate(stationsProvider);
                          if (context.mounted) {
                            Navigator.of(context).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  station.isFavourite
                                      ? 'Station removed from favourites.'
                                      : 'Station added to favourites.',
                                ),
                              ),
                            );
                          }
                        } catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(friendlyErrorMessage(error)),
                              ),
                            );
                          }
                        }
                      },
                      icon: Icon(
                        station.isFavourite
                            ? Icons.favorite
                            : Icons.favorite_border,
                      ),
                    ),
                  ],
                ),
                Text(
                  '${cleanDisplayText(station.address)}\n${cleanDisplayText(station.localAuthority)} · ${cleanDisplayText(station.indoorOutdoor)}',
                ),
                const SizedBox(height: 12),
                FutureBuilder<Map<String, dynamic>?>(
                  future: ref
                      .read(stationRepositoryProvider)
                      .loadStationRatingSummary(station.id),
                  builder: (context, snapshot) {
                    final summary = snapshot.data;
                    final average =
                        (summary?['average_rating'] as num?)?.toDouble();
                    final count =
                        (summary?['rating_count'] as num?)?.toInt() ?? 0;
                    return Row(
                      children: [
                        Icon(
                          Icons.star_rounded,
                          color: Theme.of(context).colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          average == null
                              ? 'No ratings yet'
                              : '${average.toStringAsFixed(2)} · $count rating${count == 1 ? '' : 's'}',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _startStationRoute(context, station, ref),
                    icon: const Icon(Icons.directions_outlined),
                    label: const Text('Route to this station'),
                  ),
                ),
                const SizedBox(height: 20),
                const SectionTitle(title: 'Charging piles'),
                const SizedBox(height: 8),
                for (final pile in station.piles)
                  _PileTile(
                    pile: pile,
                    canUse:
                        user.isAuthenticated &&
                        user.vehicle.connectorTypes.contains(
                          pile.connectorType,
                        ),
                  ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed:
                      user.isAuthenticated
                          ? () => _showReport(context, station)
                          : () => context.push('/auth'),
                  icon: const Icon(Icons.report_outlined),
                  label: const Text('Report a hazard'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed:
                      user.isAuthenticated
                          ? () => _showRating(context, station)
                          : () => context.push('/auth'),
                  icon: const Icon(Icons.star_outline_rounded),
                  label: const Text('Rate this station'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _startStationRoute(
    BuildContext context,
    ChargingStation station,
    WidgetRef ref,
  ) async {
    final user = ref.read(sessionProvider);
    if (!user.isAuthenticated) {
      context.push('/auth');
      return;
    }
    if (!await _allowRouteWhileCharging(context, user)) return;
    if (!context.mounted) return;
    final origin = currentLocation;
    if (origin == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tap the location icon on the map before starting a route.',
          ),
        ),
      );
      return;
    }
    if (!context.mounted) return;
    final arrivalLocation = await context.push<GeoLocation>(
      '/navigation',
      extra: NavigationRequest(origin: origin, station: station),
    );
    if (!context.mounted || arrivalLocation == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder:
          (_) => _ArrivalPileDashboard(
            station: station,
            currentLocation: arrivalLocation,
          ),
    );
  }

  Future<bool> _allowRouteWhileCharging(
    BuildContext context,
    SessionController user,
  ) async {
    if (user.activeSession == null) return true;
    await showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Charging still in progress'),
            content: const Text(
              'Please unplug and complete your current charging session before routing to another station.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('OK'),
              ),
            ],
          ),
    );
    return false;
  }

  void _showReport(BuildContext context, ChargingStation station) {
    showDialog<void>(
      context: context,
      builder: (_) => _ReportHazardDialog(station: station),
    );
  }

  void _showRating(BuildContext context, ChargingStation station) {
    showDialog<void>(
      context: context,
      builder: (_) => _StationRatingDialog(station: station),
    );
  }
}

class _StationRatingDialog extends ConsumerStatefulWidget {
  const _StationRatingDialog({required this.station});

  final ChargingStation station;

  @override
  ConsumerState<_StationRatingDialog> createState() =>
      _StationRatingDialogState();
}

class _StationRatingDialogState extends ConsumerState<_StationRatingDialog> {
  final _comment = TextEditingController();
  int _rating = 0;
  bool _saving = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rate this station'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(cleanDisplayText(widget.station.name)),
        const SizedBox(height: 14),
        const Text('How was your charging experience?'),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            5,
            (index) => IconButton(
              tooltip: '${index + 1} star${index == 0 ? '' : 's'}',
              onPressed:
                  _saving ? null : () => setState(() => _rating = index + 1),
              icon: Icon(
                index < _rating
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                color:
                    index < _rating
                        ? const Color(0xFFE2A51B)
                        : Theme.of(context).colorScheme.outline,
                size: 30,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _comment,
          maxLength: 500,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Optional comment',
            hintText: 'Share what worked well or needs improvement.',
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _submit,
        child: Text(_saving ? 'Saving...' : 'Submit rating'),
      ),
    ],
  );

  Future<void> _submit() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a star rating first.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(stationRepositoryProvider)
          .submitStationRating(
            stationId: widget.station.id,
            rating: _rating,
            comment: _comment.text,
          );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thank you for rating this station.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _ReportHazardDialog extends ConsumerStatefulWidget {
  const _ReportHazardDialog({required this.station});

  final ChargingStation station;

  @override
  ConsumerState<_ReportHazardDialog> createState() =>
      _ReportHazardDialogState();
}

class _ReportHazardDialogState extends ConsumerState<_ReportHazardDialog> {
  final note = TextEditingController();
  String category = 'Broken plug';
  String? pileId;
  bool submitting = false;
  final List<Uint8List> imageBytes = [];
  final List<String> imageNames = [];

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Report a hazard'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(cleanDisplayText(widget.station.name)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: category,
            decoration: const InputDecoration(labelText: 'Hazard type'),
            items:
                const ['Broken plug', 'ICEing', 'Locked gate', 'Safety issue']
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
            onChanged: (value) => setState(() => category = value!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            value: pileId,
            decoration: const InputDecoration(labelText: 'Related pile'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Station general'),
              ),
              ...widget.station.piles.map(
                (pile) => DropdownMenuItem<String?>(
                  value: pile.id,
                  child: Text('${pile.label} (${pile.connectorType})'),
                ),
              ),
            ],
            onChanged: (value) => setState(() => pileId = value),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: note,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'What happened?',
              hintText: 'Describe the issue for the administrator.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed:
                submitting || imageBytes.length == 5 ? null : _pickPhotos,
            icon: const Icon(Icons.add_a_photo_outlined),
            label: Text(
              imageBytes.isEmpty
                  ? 'Add photo evidence'
                  : 'Add photos (${imageBytes.length}/5)',
            ),
          ),
          if (imageBytes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Attached photos · swipe to review before submitting',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 104,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: imageBytes.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder:
                    (context, index) => Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(
                            imageBytes[index],
                            width: 130,
                            height: 104,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 3,
                          right: 3,
                          child: Material(
                            color: Colors.black54,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap:
                                  submitting
                                      ? null
                                      : () => setState(() {
                                        imageBytes.removeAt(index);
                                        imageNames.removeAt(index);
                                      }),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(
                                  Icons.close,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
              ),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: submitting ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: submitting ? null : _submit,
        child: Text(submitting ? 'Submitting...' : 'Submit report'),
      ),
    ],
  );

  Future<void> _submit() async {
    if (note.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe the hazard.')),
      );
      return;
    }
    setState(() => submitting = true);
    try {
      await ref
          .read(stationRepositoryProvider)
          .createHazardReport(
            stationId: widget.station.id,
            pileId: pileId,
            category: category,
            note: note.text,
            imageBytes: imageBytes,
            imageNames: imageNames,
          );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hazard report submitted successfully. Thank you.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _pickPhotos() async {
    try {
      final images = await ImagePicker().pickMultiImage(
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (images.isEmpty) return;
      final remaining = 5 - imageBytes.length;
      final selected = images.take(remaining).toList();
      final bytes = await Future.wait(
        selected.map((image) => image.readAsBytes()),
      );
      if (mounted) {
        setState(() {
          imageBytes.addAll(bytes);
          imageNames.addAll(selected.map((image) => image.name));
        });
        if (images.length > remaining) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Only five photos can be attached to one report.'),
            ),
          );
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not select photo. Please try again.')),
        );
      }
    }
  }
}

class _PileTile extends StatelessWidget {
  const _PileTile({required this.pile, required this.canUse});

  final ChargingPile pile;
  final bool canUse;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${cleanDisplayText(pile.label)} · ${cleanDisplayText(pile.connectorType)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '${pile.powerKw.toStringAsFixed(0)} kW · RM ${pile.pricePerKwh.toStringAsFixed(2)}/kWh',
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StatusPill(status: pile.status),
              if (!canUse) ...[
                const SizedBox(height: 6),
                const Text('Not compatible', style: TextStyle(fontSize: 11)),
              ],
            ],
          ),
        ],
      ),
    ),
  );
}

class _ChargeSetup {
  const _ChargeSetup({required this.startSoc, required this.targetSoc});

  final int startSoc;
  final int targetSoc;
}

class _ChargeSetupDialog extends StatefulWidget {
  const _ChargeSetupDialog({required this.vehicle, required this.pile});

  final VehicleProfile vehicle;
  final ChargingPile pile;

  @override
  State<_ChargeSetupDialog> createState() => _ChargeSetupDialogState();
}

class _ChargeSetupDialogState extends State<_ChargeSetupDialog> {
  late final TextEditingController current;
  late final TextEditingController target;
  String? error;

  @override
  void initState() {
    super.initState();
    current = TextEditingController(text: '20');
    target = TextEditingController(text: '${widget.vehicle.targetSoc}');
    current.addListener(_refresh);
    target.addListener(_refresh);
  }

  @override
  void dispose() {
    current.dispose();
    target.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  Duration? get estimate {
    final start = int.tryParse(current.text);
    final end = int.tryParse(target.text);
    if (start == null || end == null || end <= start) return null;
    return estimateChargingDuration(
      batteryKwh: widget.vehicle.batteryKwh,
      stationPowerKw: math.min(
        widget.pile.powerKw,
        widget.vehicle.maxChargePowerKw,
      ),
      startSoc: start,
      targetSoc: end,
    );
  }

  @override
  Widget build(BuildContext context) {
    final duration = estimate;
    return AlertDialog(
      title: const Text('Set charging target'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.vehicle.displayName} · ${widget.pile.powerKw.toStringAsFixed(0)} kW',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: current,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Current battery (%)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: target,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Target battery (%)',
                helperText:
                    'Default: ${widget.vehicle.targetSoc}% from your EV profile',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (duration != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Estimated charging time: ${_formatDuration(duration)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Based on ${math.min(widget.pile.powerKw, widget.vehicle.maxChargePowerKw).toStringAsFixed(0)} kW effective power, ${widget.vehicle.batteryKwh.toStringAsFixed(1)} kWh battery, and high-SOC tapering.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
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
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final start = int.tryParse(current.text);
            final end = int.tryParse(target.text);
            if (start == null ||
                end == null ||
                start < 0 ||
                end > 100 ||
                end <= start) {
              setState(
                () =>
                    error =
                        'Enter a current value from 0-99% and a higher target up to 100%.',
              );
              return;
            }
            Navigator.pop(
              context,
              _ChargeSetup(startSoc: start, targetSoc: end),
            );
          },
          child: const Text('Start charging'),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.inMinutes < 60) return '${duration.inMinutes} minutes';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    return minutes == 0 ? '$hours hours' : '$hours hours $minutes minutes';
  }
}

class _ArrivalPileDashboard extends ConsumerWidget {
  const _ArrivalPileDashboard({
    required this.station,
    required this.currentLocation,
  });

  final ChargingStation station;
  final GeoLocation currentLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final compatible =
        station.piles
            .where(
              (pile) =>
                  session.vehicle.connectorTypes.contains(pile.connectorType),
            )
            .toList();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .88,
        ),
        child: Scrollbar(
          thumbVisibility: true,
          child: SingleChildScrollView(
            primary: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose a charging pile',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(cleanDisplayText(station.name)),
                const SizedBox(height: 8),
                const Text(
                  'You have arrived. Select an available compatible pile to start charging now.',
                ),
                const SizedBox(height: 16),
                if (compatible.isEmpty)
                  const Text('No piles match your vehicle connector profile.'),
                for (final pile in compatible)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      title: Text(
                        '${cleanDisplayText(pile.label)} · ${cleanDisplayText(pile.connectorType)}',
                      ),
                      subtitle: Text(
                        '${pile.powerKw.toStringAsFixed(0)} kW · RM ${pile.pricePerKwh.toStringAsFixed(2)}/kWh',
                      ),
                      trailing: SizedBox(
                        width: 118,
                        child:
                            pile.status == PileStatus.available &&
                                    session.activeSession == null
                                ? FilledButton(
                                  onPressed:
                                      () => _startCharging(context, ref, pile),
                                  child: const Text('Start'),
                                )
                                : StatusPill(status: pile.status),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  'GPS: ${currentLocation.latitude.toStringAsFixed(5)}, ${currentLocation.longitude.toStringAsFixed(5)}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _startCharging(
    BuildContext context,
    WidgetRef ref,
    ChargingPile pile,
  ) async {
    final vehicle = ref.read(sessionProvider).vehicle;
    final setup = await showDialog<_ChargeSetup>(
      context: context,
      builder: (_) => _ChargeSetupDialog(vehicle: vehicle, pile: pile),
    );
    if (setup == null || !context.mounted) return;
    try {
      final effectivePowerKw = math.min(pile.powerKw, vehicle.maxChargePowerKw);
      final charging = (await ref
          .read(stationRepositoryProvider)
          .startCharging(
            stationId: station.id,
            pileId: pile.id,
            location: currentLocation,
            startSoc: setup.startSoc,
            targetSoc: setup.targetSoc,
          )).copyWith(
        stateOfCharge: setup.startSoc,
        startSoc: setup.startSoc,
        targetSoc: setup.targetSoc,
        chargePowerKw: effectivePowerKw,
        batteryKwh: vehicle.batteryKwh,
        startedAt: DateTime.now(),
      );
      ref.read(sessionProvider).setActiveSession(charging);
      if (!context.mounted) return;
      Navigator.of(context).pop();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${pile.label} selected. Charging started.')),
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
      }
    }
  }
}
