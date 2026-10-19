import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:raad/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('dashboard opens without requiring the network', (tester) async {
    await tester.pumpWidget(const RaadApp());
    await tester.pumpAndSettle();

    expect(find.text('مرکز فرماندهی بازیکن'), findsOneWidget);
    expect(find.text('جست‌وجوی پروفایل'), findsWidgets);
    expect(find.text('مقایسهٔ بازیکنان'), findsWidgets);
  });
}
