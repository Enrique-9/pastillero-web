import 'package:flutter_test/flutter_test.dart';
import 'package:pastillero_app/main.dart';

void main() {
  testWidgets('La aplicación inicia correctamente', (tester) async {
    await tester.pumpWidget(const PastilleroApp());

    expect(find.text('Mi Pastillero'), findsOneWidget);
  });
}