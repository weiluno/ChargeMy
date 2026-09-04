import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/charging_models.dart';
import '../../core/app_state.dart';
import '../../core/widgets.dart';

class ChargingHistoryScreen extends ConsumerStatefulWidget {
  const ChargingHistoryScreen({super.key});

  @override
  ConsumerState<ChargingHistoryScreen> createState() =>
      _ChargingHistoryScreenState();
}

class _ChargingHistoryScreenState extends ConsumerState<ChargingHistoryScreen> {
  late Future<List<ChargingPayment>> _payments;

  @override
  void initState() {
    super.initState();
    _payments = ref.read(stationRepositoryProvider).loadMyPayments();
  }

  void _reload() {
    setState(() {
      _payments = ref.read(stationRepositoryProvider).loadMyPayments();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Charging history'),
      actions: [
        IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
      ],
    ),
    body: FutureBuilder<List<ChargingPayment>>(
      future: _payments,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                friendlyErrorMessage(
                  snapshot.error,
                  fallback:
                      'Could not load charging history. Please try again.',
                ),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final payments = snapshot.data ?? const <ChargingPayment>[];
        if (payments.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Text(
                'No completed charging payments yet. Your e-invoices will appear here after your next successful payment.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: payments.length,
          itemBuilder:
              (context, index) => _PaymentCard(payment: payments[index]),
        );
      },
    ),
  );
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.payment});

  final ChargingPayment payment;

  @override
  Widget build(BuildContext context) {
    final date = payment.paidAt;
    final dateText =
        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    payment.stationName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.check_circle, size: 16),
                  label: Text(
                    payment.status == 'paid' ? 'Paid' : payment.status,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(dateText, style: Theme.of(context).textTheme.bodySmall),
            const Divider(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${payment.energyKwh.toStringAsFixed(2)} kWh'),
                Text(
                  'RM ${payment.amountMyr.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'E-invoice recorded for this charging session.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
