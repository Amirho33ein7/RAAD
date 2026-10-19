import 'package:flutter/material.dart';
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
    expect(find.text('کلیپ‌های من'), findsWidgets);
  });

  testWidgets('drawer routes to rank, compare, clips and sync pages', (tester) async {
    await tester.pumpWidget(const RaadApp());
    await tester.pumpAndSettle();

    Future<void> openPage(String label) async {
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      final menuLabel = find.descendant(
        of: find.byType(Drawer),
        matching: find.text(label),
      );
      expect(menuLabel, findsOneWidget, reason: 'Drawer item "$label" should exist');
      await tester.tap(menuLabel);
      await tester.pumpAndSettle();
    }

    await openPage('ردیاب رنک');
    expect(find.text('هنوز رکوردی نداری'), findsOneWidget);

    await openPage('مقایسهٔ بازیکنان');
    expect(find.text('مقایسهٔ دو پروفایل'), findsOneWidget);

    await openPage('کلیپ‌های من');
    expect(find.text('کتابخانه خالی است'), findsOneWidget);

    await openPage('تاریخچهٔ همگام‌سازی');
    expect(find.text('رخدادی ثبت نشده'), findsOneWidget);
  });
}
