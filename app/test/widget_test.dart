import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:raad/main.dart';
import 'package:raad/services/local_persistence_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // File reads/writes run on real platform I/O. Pumping frames alone doesn't
  // wait for those futures, so yield to the real event loop until the resulting
  // widget appears; if it never appears, the assertion still fails.
  Future<void> pumpUntilFound(WidgetTester tester, Finder finder) async {
    for (var attempt = 0; attempt < 40; attempt++) {
      if (finder.evaluate().isNotEmpty) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      await tester.pumpAndSettle();
    }
  }
  Directory? testStoreDirectory;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final directory =
        await Directory.systemTemp.createTemp('raad-widget-state-');
    testStoreDirectory = directory;
    // Capture this test's immutable directory; never let a late async write
    // from a previous widget test follow the mutable outer variable.
    LocalPersistenceService.directoryProviderOverride = () async => directory;
  });

  tearDown(() async {
    LocalPersistenceService.directoryProviderOverride = null;
    final directory = testStoreDirectory;
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
    testStoreDirectory = null;
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

    await openPage('تنظیمات');
    expect(find.text('ذخیرهٔ فایل کلیپ در فایل‌های گوشی'), findsOneWidget);
    expect(find.text('درخواست / بررسی دسترسی ذخیرهٔ فایل'), findsOneWidget);
  });

  testWidgets('saved player profiles can be reopened by their saved UID', (tester) async {
    SharedPreferences.setMockInitialValues({
      'raad.savedPlayers.v1': [
        jsonEncode({
          'query': 'UID-12345',
          'nickname': 'NightOwl',
          'shortId': 'ID-7788',
          'profile': {
            'nickname': 'NightOwl',
            'level': 88,
            'customReadableMpRank': 'Master III',
            'rating': 5420,
            'shortId': 'ID-7788',
            'country': 'US',
          },
          'saved_at': '2026-10-20T12:00:00.000',
        }),
      ],
    });

    await tester.pumpWidget(const RaadApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(Drawer),
      matching: find.text('پروفایل کالاف'),
    ));
    await tester.pumpAndSettle();

    await pumpUntilFound(tester, find.text('بازیکنان ذخیره‌شده (1)'));
    expect(find.text('بازیکنان ذخیره‌شده (1)'), findsOneWidget);
    expect(find.text('NightOwl'), findsOneWidget);
    await tester.tap(find.byTooltip('بازکردن پروفایل ذخیره‌شده'));
    await tester.pumpAndSettle();

    final searchField = tester.widget<TextField>(find.byType(TextField).first);
    expect(searchField.controller?.text, 'UID-12345');
    final rankFinder = find.text('Master III', skipOffstage: false);
    await tester.scrollUntilVisible(
      rankFinder,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(rankFinder, findsOneWidget);
  });

  testWidgets('saved profile survives closing and reopening the app', (tester) async {
    SharedPreferences.setMockInitialValues({
      'raad.profileCache.v1': jsonEncode({
        'nickname': 'NightOwl',
        'shortId': 'ID-7788',
        'level': 88,
        'customReadableMpRank': 'Master III',
        'rating': 5420,
        'country': 'US',
      }),
      'raad.lastProfileQuery.v1': 'UID-12345',
    });

    await tester.pumpWidget(const RaadApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(Drawer),
      matching: find.text('پروفایل کالاف'),
    ));
    await tester.pumpAndSettle();

    final saveButton = find.text('ذخیرهٔ این بازیکن');
    await pumpUntilFound(tester, saveButton);
    await tester.scrollUntilVisible(
      saveButton,
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(saveButton, findsOneWidget);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    final savedList = find.text('بازیکنان ذخیره‌شده (1)');
    await pumpUntilFound(tester, savedList);
    expect(savedList, findsOneWidget, reason: 'the saved profile must appear after the durable write');

    // Simulate a full process restart and loss of the old preferences mirror.
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    await tester.pumpWidget(const RaadApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(Drawer),
      matching: find.text('پروفایل کالاف'),
    ));
    await tester.pumpAndSettle();

    await pumpUntilFound(tester, find.text('بازیکنان ذخیره‌شده (1)'));
    expect(find.text('بازیکنان ذخیره‌شده (1)'), findsOneWidget);
    expect(find.text('NightOwl'), findsOneWidget);
  });

  testWidgets('clip links can be added and removed locally', (tester) async {
    await tester.pumpWidget(const RaadApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(Drawer),
      matching: find.text('کلیپ‌های من'),
    ));
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('کتابخانه خالی است'));

    await tester.tap(find.text('افزودن لینک کلیپ'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'https://example.com/my-clip');
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    final savedClipLink = find.text('https://example.com/my-clip');
    await pumpUntilFound(tester, savedClipLink);
    expect(savedClipLink, findsOneWidget, reason: 'the clip link should appear after the durable write');
    await tester.scrollUntilVisible(
      savedClipLink,
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(savedClipLink, findsOneWidget);
    expect(find.text('کتابخانه خالی است'), findsNothing);

    await tester.tap(find.byTooltip('حذف'));
    await tester.pumpAndSettle();

    expect(find.text('https://example.com/my-clip'), findsNothing);
    expect(find.text('کتابخانه خالی است'), findsOneWidget);
  });


  testWidgets('level leaderboard sorts players by saved level growth', (tester) async {
    SharedPreferences.setMockInitialValues({
      'raad.rankHistory.v1': [
        // Intentionally unordered: leaderboard must use timestamps, not list order.
        jsonEncode({
          'nickname': 'FastLeveler',
          'shortId': 'FAST-1',
          'level': 30,
          'saved_at': '2026-10-10T12:00:00.000',
        }),
        jsonEncode({
          'nickname': 'SlowLeveler',
          'shortId': 'SLOW-1',
          'level': 17,
          'saved_at': '2026-10-20T12:00:00.000',
        }),
        jsonEncode({
          'nickname': 'FastLeveler',
          'shortId': 'FAST-1',
          'level': 40,
          'saved_at': '2026-10-20T12:00:00.000',
        }),
        jsonEncode({
          'nickname': 'SlowLeveler',
          'shortId': 'SLOW-1',
          'level': 12,
          'saved_at': '2026-10-10T12:00:00.000',
        }),
      ],
    });

    await tester.pumpWidget(const RaadApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(Drawer),
      matching: find.text('ردیاب رنک'),
    ));
    await tester.pumpAndSettle();

    await pumpUntilFound(tester, find.text('رتبه‌بندی بر اساس پیشرفت لول'));
    expect(find.text('رتبه‌بندی بر اساس پیشرفت لول'), findsOneWidget);
    await pumpUntilFound(tester, find.text('+10 لول'));
    expect(find.text('+10 لول'), findsOneWidget);
    expect(find.text('+5 لول'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('FastLeveler').first).dy,
      lessThan(tester.getTopLeft(find.text('SlowLeveler').first).dy),
    );
  });

}
