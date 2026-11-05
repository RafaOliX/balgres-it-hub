import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:balgres_it_shell/main.dart';

void main() {
  testWidgets('Dashboard renderiza tarjetas', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DashboardPage()));
    expect(find.text('Balgres IT Hub'), findsOneWidget);
    expect(find.text('Inventario'), findsOneWidget);
  });
}
