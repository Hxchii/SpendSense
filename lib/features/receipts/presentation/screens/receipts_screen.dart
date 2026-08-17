import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:spendsense/core/widgets/empty_state.dart';
import 'package:spendsense/features/profile_settings/application/user_profile_providers.dart';
import 'package:spendsense/features/receipts/application/receipt_providers.dart';

class ReceiptsScreen extends ConsumerWidget {
  const ReceiptsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receipts = ref.watch(receiptListProvider);
    final currency = ref.watch(userProfileProvider).valueOrNull?.currencySymbol ?? '₱';

    return Scaffold(
      appBar: AppBar(title: const Text('Receipts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/receipts/scan'),
        icon: const Icon(LucideIcons.camera),
        label: const Text('Scan'),
      ),
      body: receipts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Something went wrong: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: LucideIcons.receipt,
              title: 'No receipts yet',
              message: 'Scan a receipt to automatically log a transaction.',
            );
          }
          final sorted = [...list]..sort((a, b) => b.date.compareTo(a.date));
          return ListView.builder(
            itemCount: sorted.length,
            itemBuilder: (context, i) {
              final r = sorted[i];
              return ListTile(
                leading: const CircleAvatar(child: Icon(LucideIcons.receipt)),
                title: Text(r.merchant),
                subtitle: Text(DateFormat.yMMMd().format(r.date)),
                trailing: Text(r.total.format(currency)),
                onTap: () => context.push('/receipts/detail', extra: r),
              );
            },
          );
        },
      ),
    );
  }
}
