import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const backendBaseUrl = String.fromEnvironment('RAAD_API_URL', defaultValue: 'http://10.0.2.2:8000');

void main() => runApp(const RaadApp());

class RaadApp extends StatelessWidget {
  const RaadApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'رعد | RAAD',
        locale: const Locale('fa', 'IR'),
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark, scaffoldBackgroundColor: const Color(0xFF080D16), colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF55E6F2), brightness: Brightness.dark), fontFamily: 'Vazirmatn'),
        home: const RaadHome(),
      );
}

class RaadHome extends StatefulWidget {
  const RaadHome({super.key});
  @override
  State<RaadHome> createState() => _RaadHomeState();
}

class _RaadHomeState extends State<RaadHome> {
  final _query = TextEditingController();
  Map<String, dynamic>? _profile;
  String? _error;
  bool _loading = false;
  int _page = 0;

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.isEmpty) { setState(() => _error = 'نام یا شناسهٔ بازیکن را وارد کن.'); return; }
    setState(() { _loading = true; _error = null; _profile = null; });
    try {
      final uri = Uri.parse('$backendBaseUrl/api/v1/codm/profile').replace(queryParameters: {'q': q});
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      final decoded = jsonDecode(response.body);
      if (response.statusCode != 200) {
        final detail = decoded is Map ? decoded['detail'] : null;
        throw Exception(detail?.toString() ?? 'دریافت اطلاعات ناموفق بود.');
      }
      if (decoded is! Map<String, dynamic>) throw Exception('پاسخ سرور معتبر نیست.');
      setState(() => _profile = decoded);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  String _value(String key) {
    final v = _profile?[key];
    if (v == null || v.toString().trim().isEmpty) return 'در دسترس نیست';
    return v.toString();
  }

  @override
  void dispose() { _query.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('رعد ⚡', style: TextStyle(fontWeight: FontWeight.bold)), actions: [IconButton(tooltip: 'دربارهٔ رعد', onPressed: () => showAboutDialog(context: context, applicationName: 'رعد | RAAD', applicationVersion: '0.1.0', children: const [Text('همراه مستقل و غیررسمی بازیکنان کالاف موبایل. داده‌ها به محدودیت سرویس خارجی وابسته‌اند.')]), icon: const Icon(Icons.info_outline))]),
          drawer: Drawer(child: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const Padding(padding: EdgeInsets.all(20), child: Text('رَعد | RAAD\nنبض رنک، زیر نظر تو', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))), const Divider(), _nav(Icons.dashboard_outlined, 'داشبورد', 0), _nav(Icons.person_search_outlined, 'پروفایل کالاف', 1), _nav(Icons.show_chart, 'ردیاب رنک', 2), _nav(Icons.compare_arrows, 'مقایسهٔ بازیکنان', 3), _nav(Icons.video_library_outlined, 'کلیپ‌های من', 4), _nav(Icons.history, 'تاریخچهٔ همگام‌سازی', 5), const Spacer(), const Padding(padding: EdgeInsets.all(16), child: Text('اتصال پروفایل از سرویس غیررسمی انجام می‌شود.', style: TextStyle(color: Colors.white60, fontSize: 12)))]))),
          body: SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
            Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF102D3C), Color(0xFF111827)]), borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFF2C6674))), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('مرکز فرماندهی بازیکن', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), SizedBox(height: 8), Text('پروفایل قابل‌دسترسی و تغییرات رنک را در یک‌جا بررسی کن.', style: TextStyle(color: Colors.white70)), SizedBox(height: 14), Row(children: [Icon(Icons.bolt, color: Color(0xFF55E6F2)), SizedBox(width: 6), Expanded(child: Text('رعد مستقل است و محصول رسمی Activision نیست.', style: TextStyle(fontSize: 12, color: Colors.white60)))])])),
            const SizedBox(height: 22), const Text('جست‌وجوی پروفایل', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 10), TextField(controller: _query, textDirection: TextDirection.ltr, onSubmitted: (_) => _search(), decoration: InputDecoration(hintText: 'نام بازیکن یا شناسه', prefixIcon: const Icon(Icons.search), filled: true, fillColor: const Color(0xFF111827), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none))), const SizedBox(height: 10), FilledButton.icon(onPressed: _loading ? null : _search, icon: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.cloud_download_outlined), label: Text(_loading ? 'در حال دریافت اطلاعات…' : 'دریافت پروفایل')),
            if (_error != null) ...[const SizedBox(height: 12), _message(Icons.error_outline, _error!, Colors.redAccent)],
            if (_profile != null) ...[const SizedBox(height: 20), const Text('اطلاعات دریافت‌شده', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 10), _stat('نام بازیکن', _value('nickname'), Icons.person_outline), _stat('لول', _value('level'), Icons.military_tech_outlined), _stat('رنک مولتی‌پلیر', _value('customReadableMpRank'), Icons.emoji_events_outlined), _stat('امتیاز رنک', _value('rating'), Icons.insights_outlined), _stat('شناسه', _value('shortId'), Icons.tag), const SizedBox(height: 8), _message(Icons.info_outline, 'منبع اطلاعات غیررسمی است. فقط فیلدهای برگشتی نمایش داده می‌شوند؛ تاریخچهٔ مسابقات و آمار کیل/دث تضمین نشده است.', Colors.cyanAccent)],
            const SizedBox(height: 22), const Text('امکانات رعد', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 10), Wrap(spacing: 10, runSpacing: 10, children: const [FeatureCard(icon: Icons.show_chart, title: 'ردیاب رنک', description: 'پس از اتصال دیتابیس'), FeatureCard(icon: Icons.compare_arrows, title: 'مقایسهٔ بازیکنان', description: 'بر پایهٔ فیلدهای مشترک'), FeatureCard(icon: Icons.video_library_outlined, title: 'کلیپ‌های من', description: 'نیازمند پیکربندی ذخیره‌سازی')]),
          ])),
        ),
      );

  Widget _nav(IconData icon, String title, int index) => ListTile(leading: Icon(icon), title: Text(title), selected: _page == index, onTap: () { setState(() => _page = index); Navigator.pop(context); if (index != 0 && index != 1) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('بخش «$title» در نسخهٔ اولیه هنوز پیاده‌سازی نشده است.'))); });
  Widget _stat(String title, String value, IconData icon) => Card(color: const Color(0xFF111827), child: ListTile(leading: Icon(icon, color: const Color(0xFF55E6F2)), title: Text(title), subtitle: SelectableText(value, textDirection: TextDirection.auto)));
  Widget _message(IconData icon, String text, Color color) => Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withValues(alpha: .08), borderRadius: BorderRadius.circular(12)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: color), const SizedBox(width: 10), Expanded(child: Text(text))]));
}

class FeatureCard extends StatelessWidget {
  final IconData icon; final String title; final String description;
  const FeatureCard({super.key, required this.icon, required this.title, required this.description});
  @override
  Widget build(BuildContext context) => SizedBox(width: 155, child: Card(color: const Color(0xFF111827), child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: const Color(0xFF55E6F2), size: 28), const SizedBox(height: 12), Text(title, style: const TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 5), Text(description, style: const TextStyle(fontSize: 12, color: Colors.white60))]))));
}
