import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:novelty_fashion/biometric_gate.dart';

void main() {
  testWidgets('keeps the app locked until device authentication succeeds', (
    WidgetTester tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      AndroidBiometricGate(
        authenticate: () async => ++attempts > 1,
        child: const MaterialApp(
          home: Scaffold(body: Text('Inventario privado')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Inventario privado'), findsNothing);
    expect(find.text('Desbloqueo seguro'), findsOneWidget);

    await tester.tap(find.text('Autenticar con biometría o PIN'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('Inventario privado'), findsOneWidget);
    expect(find.text('Desbloqueo seguro'), findsNothing);
  });

  testWidgets('no vuelve a pedir biometría al regresar del segundo plano', (
    WidgetTester tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      AndroidBiometricGate(
        authenticate: () async {
          attempts++;
          return true;
        },
        child: const MaterialApp(
          home: Scaffold(body: Text('Inventario privado')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(attempts, 1);
    expect(find.text('Inventario privado'), findsOneWidget);
    expect(find.text('Desbloqueo biométrico'), findsNothing);
  });
}
