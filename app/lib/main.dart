import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'services/codm_profile_service.dart';

const backendBaseUrl = String.fromEnvironment('RAAD_API_URL', defaultValue: 'https://callofdutymobile.vercel.app');
const bool useBackend = bool.fromEnvironment('RAAD_USE_BACKEND', defaultValue: false);
const accent = Color(0xFF55E6F2);
const panel = Color(0xFF111827);

void main() => runApp(const RaadApp());

class RaadApp extends StatelessWidget {
  const RaadApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'رعد | RAAD',
    locale: const Locale('fa', 'IR'),
    theme: ThemeData(useMaterial3: true, brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF080D16),
      colorScheme: ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.dark)),
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
  final _compareQuery = TextEditingController();
  late final CodmProfileService _profileService = CodmProfileService(
    baseUrl: backendBaseUrl,
    useBackend: useBackend,
  );
  Map<String, dynamic>? _profile, _otherProfile;
  String? _error, _compareError;
  bool _loading = false, _compareLoading = false;
  int _page = 0;
  List<Map<String, dynamic>> _rankHistory = [];
  List<String> _clips = [], _events = [];

  @override
  void initState() { super.initState(); _loadLocal(); }

  Future<void> _loadLocal() async {
    try {
      final p = await SharedPreferences.getInstance();
      final rows = <Map<String, dynamic>>[];
      for (final raw in p.getStringList('raad.rankHistory.v1') ?? <String>[]) {
        try {
          final v = jsonDecode(raw);
          if (v is Map) rows.add(Map<String, dynamic>.from(v));
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _rankHistory = rows;
        _clips = p.getStringList('raad.clips.v1') ?? [];
        _events = p.getStringList('raad.events.v1') ?? [];
      });
    } catch (_) {
      _recordEvent('بارگذاری اطلاعات محلی ناموفق بود.');
    }
  }

  Future<Map<String, dynamic>> _fetchProfile(String q) =>
      _profileService.fetchProfile(q);

  String _errorText(Object error) {
    final msg = error.toString().replaceFirst('Exception: ', '');
    if (msg.contains('SocketException') || error is http.ClientException) return 'اتصال به سرور رعد برقرار نشد؛ آدرس API و اتصال را بررسی کن.';
    if (msg.contains('TimeoutException')) return 'پاسخ سرویس بیش از حد طول کشید. دوباره تلاش کن.';
    return msg;
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.isEmpty) { setState(() => _error = 'نام یا شناسهٔ بازیکن را وارد کن.'); return; }
    setState(() { _loading = true; _error = null; });
    try {
      final result = await _fetchProfile(q);
      if (!mounted) return;
      setState(() => _profile = result);
      await _recordEvent('پروفایل ' + q + ' دریافت شد.');
    } catch (e) {
      final message = _errorText(e);
      if (mounted) setState(() => _error = message);
      await _recordEvent('دریافت پروفایل ' + q + ' ناموفق بود: ' + message);
    } finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _compare() async {
    final q = _compareQuery.text.trim();
    if (_profile == null) { setState(() => _compareError = 'ابتدا پروفایل اول را در بخش پروفایل دریافت کن.'); return; }
    if (q.isEmpty) { setState(() => _compareError = 'نام یا شناسهٔ بازیکن دوم را وارد کن.'); return; }
    setState(() { _compareLoading = true; _compareError = null; _otherProfile = null; });
    try {
      final other = await _fetchProfile(q);
      if (mounted) setState(() => _otherProfile = other);
      await _recordEvent('پروفایل دوم برای مقایسه دریافت شد: ' + q);
    } catch (e) {
      final message = _errorText(e);
      if (mounted) setState(() => _compareError = message);
      await _recordEvent('مقایسه ناموفق بود: ' + message);
    } finally { if (mounted) setState(() => _compareLoading = false); }
  }

  String _value(Map<String, dynamic>? p, String key) {
    final v = p?[key];
    return v == null || v.toString().trim().isEmpty ? 'در دسترس نیست' : v.toString();
  }

  Future<void> _recordEvent(String message) async {
    final timestamp = DateTime.now().toLocal().toString().split('.').first;
    final next = [timestamp + ' — ' + message, ..._events].take(100).toList();
    if (mounted) setState(() => _events = next);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList('raad.events.v1', next);
    } catch (_) {}
  }

  Future<void> _saveSnapshot() async {
    if (_profile == null) { _toast('اول یک پروفایل دریافت کن.'); return; }
    final snapshot = <String, dynamic>{
      'nickname': _profile!['nickname'], 'level': _profile!['level'],
      'customReadableMpRank': _profile!['customReadableMpRank'], 'rating': _profile!['rating'],
      'shortId': _profile!['shortId'], 'saved_at': DateTime.now().toIso8601String(),
    };
    final next = [snapshot, ..._rankHistory].take(50).toList();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList('raad.rankHistory.v1', next.map(jsonEncode).toList());
      if (!mounted) return;
      setState(() => _rankHistory = next);
      await _recordEvent('رکورد رنک روی دستگاه ذخیره شد.');
      _toast('رکورد روی همین دستگاه ذخیره شد.');
    } catch (_) { _toast('ذخیرهٔ رکورد ناموفق بود.'); }
  }

  Future<void> _addClip() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('افزودن لینک کلیپ'),
      content: TextField(controller: controller, autofocus: true, textDirection: TextDirection.ltr,
        keyboardType: TextInputType.url, decoration: const InputDecoration(hintText: 'https://...')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('ذخیره')),
      ],
    ));
    controller.dispose();
    if (url == null || url.isEmpty) return;
    final parsed = Uri.tryParse(url);
    if (parsed == null || !parsed.hasAuthority || !['https', 'http'].contains(parsed.scheme)) {
      _toast('لینک معتبر HTTP یا HTTPS وارد کن.'); return;
    }
    if (_clips.contains(url)) { _toast('این لینک از قبل ذخیره شده.'); return; }
    final next = [url, ..._clips];
    final p = await SharedPreferences.getInstance();
    await p.setStringList('raad.clips.v1', next);
    if (!mounted) return;
    setState(() => _clips = next);
    await _recordEvent('لینک کلیپ محلی ذخیره شد.');
  }

  Future<void> _removeClip(String url) async {
    final next = _clips.where((e) => e != url).toList();
    final p = await SharedPreferences.getInstance();
    await p.setStringList('raad.clips.v1', next);
    if (mounted) setState(() => _clips = next);
  }

  Future<void> _clearHistory() async {
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('پاک‌کردن تاریخچه؟'),
      content: const Text('رکوردهای ذخیره‌شده روی همین دستگاه حذف می‌شوند.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('پاک کن')),
      ],
    ));
    if (yes != true) return;
    final p = await SharedPreferences.getInstance();
    await p.remove('raad.rankHistory.v1');
    if (mounted) setState(() => _rankHistory = []);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
  void _go(int page) { Navigator.pop(context); setState(() => _page = page); }

  @override
  void dispose() {
    _query.dispose();
    _compareQuery.dispose();
    _profileService.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl, child: Scaffold(
    appBar: AppBar(title: const Text('رعد ⚡', style: TextStyle(fontWeight: FontWeight.bold)),
      actions: [IconButton(icon: const Icon(Icons.info_outline), tooltip: 'دربارهٔ رعد', onPressed: () => showAboutDialog(
        context: context, applicationName: 'رعد | RAAD', applicationVersion: '0.2.0',
        children: const [Text('اپ مستقل و غیررسمی برای نمایش فیلدهای قابل‌دسترسی پروفایل CODM.'), Text('رمز عبور بازی درخواست نمی‌شود.')]))]),
    drawer: Drawer(child: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Padding(padding: EdgeInsets.all(20), child: Text('رَعد | RAAD\nنبض رنک، زیر نظر تو', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
      const Divider(),
      _nav(Icons.dashboard_outlined, 'داشبورد', 0),
      _nav(Icons.person_search_outlined, 'پروفایل کالاف', 1),
      _nav(Icons.show_chart, 'ردیاب رنک', 2),
      _nav(Icons.compare_arrows, 'مقایسهٔ بازیکنان', 3),
      _nav(Icons.video_library_outlined, 'کلیپ‌های من', 4),
      _nav(Icons.history, 'تاریخچهٔ همگام‌سازی', 5),
      const Spacer(),
      const Padding(padding: EdgeInsets.all(16), child: Text('رکوردها و لینک‌ها محلی هستند. سرور پروفایل، غیررسمی است.', style: TextStyle(color: Colors.white60, fontSize: 12))),
    ]))),
    body: SafeArea(child: AnimatedSwitcher(duration: const Duration(milliseconds: 180),
      child: KeyedSubtree(key: ValueKey<int>(_page), child: _body()))),
  ));

  Widget _body() {
    switch (_page) {
      case 1: return _profilePage();
      case 2: return _rankPage();
      case 3: return _comparePage();
      case 4: return _clipsPage();
      case 5: return _eventsPage();
      default: return _dashboard();
    }
  }

  Widget _dashboard() => ListView(padding: const EdgeInsets.all(18), children: [
    Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [Color(0xFF102D3C), Color(0xFF111827)]),
      borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFF2C6674))),
      child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('مرکز فرماندهی بازیکن', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        SizedBox(height: 8),
        Text('پروفایل قابل‌دسترسی را ببین، رکورد رنک بساز و دو پروفایل را کنار هم بررسی کن.', style: TextStyle(color: Colors.white70)),
        SizedBox(height: 12), Text('رعد مستقل است و محصول رسمی Activision نیست.', style: TextStyle(color: accent, fontSize: 12)),
      ])),
    const SizedBox(height: 20), _heading('دسترسی سریع'),
    _action(Icons.person_search, 'جست‌وجوی پروفایل', 'نام یا شناسهٔ بازیکن', () => setState(() => _page = 1)),
    _action(Icons.show_chart, 'ردیاب رنک', _rankHistory.length.toString() + ' رکورد ذخیره‌شده', () => setState(() => _page = 2)),
    _action(Icons.compare_arrows, 'مقایسهٔ بازیکنان', 'مقایسهٔ فیلدهای واقعی و مشترک', () => setState(() => _page = 3)),
    _action(Icons.video_library_outlined, 'کلیپ‌های من', _clips.length.toString() + ' لینک ذخیره‌شده', () => setState(() => _page = 4)),
    if (_profile != null) ...[const SizedBox(height: 16), _heading('آخرین پروفایل'), _profileCard(_profile!)],
    const SizedBox(height: 12),
    _notice('حریم خصوصی', 'رمز عبور بازی را وارد نکن. تاریخچه و لینک‌ها روی همین دستگاه ذخیره می‌شوند.'),
  ]);

  Widget _profilePage() => ListView(padding: const EdgeInsets.all(18), children: [
    _heading('جست‌وجوی پروفایل'),
    const SizedBox(height: 8),
    const Text('فقط فیلدهایی نمایش داده می‌شوند که سرویس برمی‌گرداند.', style: TextStyle(color: Colors.white60)),
    const SizedBox(height: 12),
    TextField(controller: _query, textDirection: TextDirection.ltr, onSubmitted: (_) => _search(),
      decoration: InputDecoration(hintText: 'نام بازیکن یا شناسه', prefixIcon: const Icon(Icons.search),
        filled: true, fillColor: panel, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none))),
    const SizedBox(height: 10),
    FilledButton.icon(onPressed: _loading ? null : _search,
      icon: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.cloud_download_outlined),
      label: Text(_loading ? 'در حال دریافت…' : 'دریافت پروفایل')),
    if (_error != null) ...[const SizedBox(height: 10), _notice('دریافت ناموفق بود', _error!, color: Colors.redAccent)],
    if (_profile != null) ...[
      const SizedBox(height: 18), _heading('نتیجهٔ دریافت‌شده'), _profileCard(_profile!),
      _field('نام بازیکن', _value(_profile, 'nickname'), Icons.person_outline),
      _field('لول', _value(_profile, 'level'), Icons.military_tech_outlined),
      _field('رنک مولتی‌پلیر', _value(_profile, 'customReadableMpRank'), Icons.emoji_events_outlined),
      _field('امتیاز رنک', _value(_profile, 'rating'), Icons.insights_outlined),
      _field('شناسه', _value(_profile, 'shortId'), Icons.tag),
      _field('کشور', _value(_profile, 'country'), Icons.public),
      const SizedBox(height: 8),
      FilledButton.tonalIcon(onPressed: _saveSnapshot, icon: const Icon(Icons.bookmark_add_outlined), label: const Text('ذخیرهٔ رکورد رنک')),
      const SizedBox(height: 10),
      _notice('محدودیت داده‌ها', 'منبع غیررسمی است. تاریخچهٔ مسابقات و آمار کیل/دث تضمین نشده و ساخته نمی‌شود.'),
    ],
  ]);

  Widget _rankPage() => ListView(padding: const EdgeInsets.all(18), children: [
    _heading('ردیاب رنک'),
    const SizedBox(height: 8),
    const Text('پروفایل را دریافت کن و هر بار رکورد ذخیره کن. روند فقط از رکوردهای واقعی که خودت ذخیره می‌کنی ساخته می‌شود؛ تاریخچهٔ گذشته جعل نمی‌شود.', style: TextStyle(color: Colors.white60)),
    const SizedBox(height: 12),
    _action(Icons.bookmark_add_outlined, 'ذخیرهٔ وضعیت فعلی', _profile == null ? 'ابتدا پروفایل دریافت کن' : _value(_profile, 'nickname'), _saveSnapshot),
    const SizedBox(height: 12), _heading('رکوردها (' + _rankHistory.length.toString() + ')'),
    if (_rankHistory.isEmpty) _empty(Icons.show_chart, 'هنوز رکوردی نداری', 'یک پروفایل دریافت کن و آن را ذخیره کن.'),
    ..._rankHistory.map((row) => Card(color: panel, child: ListTile(
      leading: const Icon(Icons.insights_outlined, color: accent),
      title: Text(row['nickname']?.toString() ?? 'نامشخص'),
      subtitle: Text('رنک: ' + _display(row['customReadableMpRank']) + ' • امتیاز: ' + _display(row['rating']) +
        '\nلول: ' + _display(row['level']) + '\n' + (row['saved_at']?.toString() ?? '').replaceFirst('T', ' ')),
      isThreeLine: true,
    ))),
    if (_rankHistory.isNotEmpty) TextButton.icon(onPressed: _clearHistory, icon: const Icon(Icons.delete_outline), label: const Text('پاک‌کردن تاریخچه')),
  ]);

  Widget _comparePage() => ListView(padding: const EdgeInsets.all(18), children: [
    _heading('مقایسهٔ دو پروفایل'),
    const SizedBox(height: 8),
    const Text('ابتدا پروفایل اول را در بخش پروفایل دریافت کن. سپس نام یا شناسهٔ نفر دوم را جست‌وجو کن.', style: TextStyle(color: Colors.white60)),
    const SizedBox(height: 12),
    if (_profile == null) _action(Icons.person_search, 'پروفایل اول را دریافت کن', 'رفتن به صفحهٔ پروفایل', () => setState(() => _page = 1)) else _profileCard(_profile!),
    const SizedBox(height: 12),
    TextField(controller: _compareQuery, textDirection: TextDirection.ltr, onSubmitted: (_) => _compare(),
      decoration: InputDecoration(hintText: 'شناسه یا نام بازیکن دوم', prefixIcon: const Icon(Icons.compare_arrows),
        filled: true, fillColor: panel, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none))),
    const SizedBox(height: 10),
    FilledButton.icon(onPressed: _compareLoading ? null : _compare,
      icon: _compareLoading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.compare),
      label: Text(_compareLoading ? 'در حال دریافت…' : 'دریافت و مقایسه')),
    if (_compareError != null) ...[const SizedBox(height: 10), _notice('خطا در مقایسه', _compareError!, color: Colors.redAccent)],
    if (_profile != null && _otherProfile != null) ...[
      const SizedBox(height: 16),
      Row(children: [Expanded(child: _playerHeader(_profile!)), const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.compare_arrows, color: accent)), Expanded(child: _playerHeader(_otherProfile!))]),
      const SizedBox(height: 10),
      _compareRow('لول', _profile!['level'], _otherProfile!['level']),
      _compareRow('امتیاز رنک', _profile!['rating'], _otherProfile!['rating']),
      _compareRow('رنک مولتی‌پلیر', _profile!['customReadableMpRank'], _otherProfile!['customReadableMpRank']),
      _compareRow('کشور', _profile!['country'], _otherProfile!['country']),
      _notice('نحوهٔ مقایسه', 'اختلاف عددی فقط زمانی محاسبه می‌شود که هر دو مقدار عددی و موجود باشند.'),
    ],
  ]);

  Widget _clipsPage() => ListView(padding: const EdgeInsets.all(18), children: [
    _heading('کلیپ‌های من'),
    const SizedBox(height: 8),
    const Text('در این نسخه لینک کلیپ‌ها ذخیره می‌شوند؛ آپلود ویدیو و فضای ابری هنوز وصل نیست. لینک‌ها روی همین دستگاه می‌مانند.', style: TextStyle(color: Colors.white60)),
    const SizedBox(height: 12),
    FilledButton.icon(onPressed: _addClip, icon: const Icon(Icons.add_link), label: const Text('افزودن لینک کلیپ')),
    const SizedBox(height: 10),
    if (_clips.isEmpty) _empty(Icons.video_library_outlined, 'کتابخانه خالی است', 'یک لینک عمومی با http یا https اضافه کن.'),
    ..._clips.map((url) => Card(color: panel, child: ListTile(
      leading: const Icon(Icons.play_circle_outline, color: accent),
      title: SelectableText(url, textDirection: TextDirection.ltr),
      subtitle: const Text('ذخیره‌شده روی دستگاه'),
      trailing: IconButton(tooltip: 'حذف', onPressed: () => _removeClip(url), icon: const Icon(Icons.delete_outline)),
    ))),
  ]);

  Widget _eventsPage() => ListView(padding: const EdgeInsets.all(18), children: [
    _heading('تاریخچهٔ همگام‌سازی'),
    const SizedBox(height: 8),
    const Text('رخدادهای محلی نمایش داده می‌شوند؛ این فهرست به معنی به‌روزرسانی خودکار پس‌زمینه نیست.', style: TextStyle(color: Colors.white60)),
    const SizedBox(height: 10),
    if (_events.isEmpty) _empty(Icons.history, 'رخدادی ثبت نشده', 'بعد از دریافت پروفایل یا ذخیره‌سازی، رویداد اینجا نمایش داده می‌شود.'),
    ..._events.map((event) => Card(color: panel, child: ListTile(leading: const Icon(Icons.history, color: accent), title: Text(event)))),
    if (_events.isNotEmpty) TextButton.icon(onPressed: () async {
      final p = await SharedPreferences.getInstance(); await p.remove('raad.events.v1');
      if (mounted) setState(() => _events = []);
    }, icon: const Icon(Icons.delete_outline), label: const Text('پاک‌کردن تاریخچه')),
  ]);

  Widget _nav(IconData icon, String title, int page) => ListTile(
    leading: Icon(icon), title: Text(title), selected: _page == page, onTap: () => _go(page));

  Widget _heading(String title) => Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold));

  Widget _action(IconData icon, String title, String subtitle, VoidCallback onTap) => Card(
    color: panel, child: ListTile(onTap: onTap, leading: Icon(icon, color: accent),
      title: Text(title), subtitle: Text(subtitle), trailing: const Icon(Icons.chevron_left)));

  Widget _profileCard(Map<String, dynamic> p) => Card(color: panel, child: ListTile(
    leading: const CircleAvatar(backgroundColor: Color(0xFF173747), child: Icon(Icons.person_outline, color: accent)),
    title: Text(_value(p, 'nickname')),
    subtitle: Text('لول: ' + _value(p, 'level') + ' • رنک: ' + _value(p, 'customReadableMpRank'))));

  Widget _field(String title, String value, IconData icon) => Card(color: panel, child: ListTile(
    leading: Icon(icon, color: accent), title: Text(title),
    subtitle: SelectableText(value, textDirection: TextDirection.ltr)));

  Widget _playerHeader(Map<String, dynamic> p) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(14), border: Border.all(color: accent.withValues(alpha: .25))),
    child: Column(children: [const Icon(Icons.person_outline, color: accent, size: 26), const SizedBox(height: 6),
      Text(_value(p, 'nickname'), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis)]));

  Widget _compareRow(String label, dynamic a, dynamic b) {
    final an = num.tryParse(a?.toString() ?? ''), bn = num.tryParse(b?.toString() ?? '');
    var extra = '';
    if (an != null && bn != null) {
      final delta = an - bn;
      extra = '\nاختلاف عددی (اول − دوم): ' + (delta > 0 ? '+' : '') + delta.toString();
    }
    return Card(color: panel, child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
      Text(label, style: const TextStyle(color: accent, fontWeight: FontWeight.bold)),
      const SizedBox(height: 7),
      Row(children: [Expanded(child: Text(_display(a), textAlign: TextAlign.center)), const Icon(Icons.compare_arrows, size: 18, color: Colors.white54), Expanded(child: Text(_display(b), textAlign: TextAlign.center))]),
      if (extra.isNotEmpty) Text(extra, style: const TextStyle(fontSize: 11, color: Colors.white54)),
    ])));
  }

  Widget _empty(IconData icon, String title, String details) => Container(
    padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(16)),
    child: Column(children: [Icon(icon, size: 34, color: accent), const SizedBox(height: 10),
      Text(title, style: const TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 5),
      Text(details, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60))]));

  Widget _notice(String title, String details, {Color color = accent}) => Container(
    padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: color.withValues(alpha: .08), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: .15))),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.info_outline, color: color), const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text(details)]))]));

  String _display(dynamic v) => v == null || v.toString().trim().isEmpty ? 'در دسترس نیست' : v.toString();
}
