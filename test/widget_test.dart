import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendsense/core/routing/app_shell.dart';
import 'package:spendsense/main.dart';

void main() {
  testWidgets('App boots to the dashboard on seeded (onboarded) profile', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: SpendSenseApp()));
    await tester.pumpAndSettle();

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.text('Deejay'), findsOneWidget);

    // The dashboard triggers the recurring-bill auto-deduct sweep on load,
    // which chains several mock-latency delays (markPaidNow -> transaction
    // create -> bill update). pumpAndSettle() only keeps pumping while a
    // frame is scheduled, so a bare Timer with nothing yet visibly pending
    // can outlive it — flush explicitly so nothing leaks into teardown.
    await tester.pump(const Duration(seconds: 2));
  });
}
