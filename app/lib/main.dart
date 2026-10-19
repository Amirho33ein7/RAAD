import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'services/codm_profile_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:google_sign_in/google_sign_in.dart';

const backendBaseUrl = String.fromEnvironment('RAAD_API_URL', defaultValue: 'https://callofdutymobile.vercel.app');
const bool useBackend = bool.fromEnvironment('RAAD_USE_BACKEND', defaultValue: false);
const String raadAppVersion = '0.3.0+3';
const String googleServerClientId = String.fromEnvironment('RAAD_GOOGLE_SERVER_CLIENT_ID');
const String githubReleasesPage = 'https://github.com/Amirho33ein7/RAAD/releases';
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
    builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child ?? const SizedBox.shrink()),
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
  Map<String, dynamic> _manualProfile = {};
  GoogleSignInAccount? _googleUser;
  String? _error, _compareError, _updateMessage, _updateApkUrl, _latestTag;
  bool _loading = false, _compareLoading = false, _checkingUpdate = false;
  int _page = 0;
  List<Map<String, dynamic>> _rankHistory = [];
  List<Map<String, dynamic>> _clips = [];
  List<String> _events = [];

  Map<String, dynamic>? get _displayProfile {
    final merged = <String, dynamic>{...? _profile};
    for (final entry in _manualProfile.entries) {
      if (entry.value != null && entry.value.toString().trim().isNotEmpty) {
        merged[entry.key] = entry.value;
      }
    }
    if (merged.isEmpty) return null;
    return merged;
  }

  @override
  void initState() {
    super.initState();
    _loadLocal();
    _restoreGoogleSession();
  }

  Future<void> _restoreGoogleSession() async {
    if (googleServerClientId.trim().isEmpty) return;
    try {
      final account = await GoogleSignIn(
        serverClientId: googleServerClientId,
        scopes: const ['email'],
      ).signInSilently();
      if (mounted && account != null) setState(() => _googleUser = account);
    } catch (_) {
      // Google login is optional until the app owner configures OAuth.
    }
  }

  Future<void> _loadLocal() async {
    try {
      final p = await SharedPreferences.getInstance();
      final rows = <Map<String, dynamic>>[];
      for (final raw in p.getStringList('raad.rankHistory.v1') ?? <String>[]) {
        try {
          final value = jsonDecode(raw);
          if (value is Map) rows.add(Map<String, dynamic>.from(value));
        } catch (_) {}
      }

      final clipRows = <Map<String, dynamic>>[];
      final storedClips = p.getStringList('raad.clips.v2') ??
          p.getStringList('raad.clips.v1') ?? <String>[];
      for (final raw in storedClips) {
        try {
          final value = jsonDecode(raw);
          if (value is Map) {
            clipRows.add(Map<String, dynamic>.from(value));
            continue;
          }
        } catch (_) {
          // Version 1 stored plain URLs instead of JSON objects.
        }
        final uri = Uri.tryParse(raw);
        if (uri != null && uri.hasAuthority && const {'http', 'https'}.contains(uri.scheme)) {
          clipRows.add({'type': 'link', 'url': raw, 'title': raw, 'description': '', 'created_at': ''});
        }
      }

      Map<String, dynamic> parseStoredMap(String key) {
        try {
          final decoded = jsonDecode(p.getString(key) ?? '');
          if (decoded is Map) return Map<String, dynamic>.from(decoded);
        } catch (_) {}
        return <String, dynamic>{};
      }

      Map<String, dynamic>? cachedProfile;
      try {
        final decoded = jsonDecode(p.getString('raad.profileCache.v1') ?? '');
        if (decoded is Map) cachedProfile = Map<String, dynamic>.from(decoded);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _rankHistory = rows;
        _clips = clipRows;
        _events = p.getStringList('raad.events.v1') ?? [];
        _manualProfile = parseStoredMap('raad.manualProfile.v1');
        _profile = cachedProfile;
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
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('raad.profileCache.v1', jsonEncode(result));
      } catch (_) {}
      await _recordEvent('پروفایل ' + q + ' دریافت شد.');
    } catch (e) {
      final message = _errorText(e);
      if (mounted) setState(() => _error = message);
      await _recordEvent('دریافت پروفایل ' + q + ' ناموفق بود: ' + message);
    } finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _compare() async {
    final q = _compareQuery.text.trim();
    if (_displayProfile == null) { setState(() => _compareError = 'ابتدا پروفایل اول را در بخش پروفایل دریافت یا دستی ثبت کن.'); return; }
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
    final profile = _displayProfile;
    if (profile == null) { _toast('اول پروفایل را جست‌وجو یا اطلاعات دستی را وارد کن.'); return; }
    final snapshot = <String, dynamic>{
      'nickname': profile['nickname'], 'level': profile['level'],
      'customReadableMpRank': profile['customReadableMpRank'], 'rating': profile['rating'],
      'shortId': profile['shortId'], 'saved_at': DateTime.now().toIso8601String(),
      'source': _manualProfile.isNotEmpty ? 'manual_or_api' : 'api',
    };
    if (_rankHistory.isNotEmpty) {
      final newest = _rankHistory.first;
      final same = ['nickname', 'level', 'customReadableMpRank', 'rating', 'shortId']
          .every((key) => newest[key]?.toString() == snapshot[key]?.toString());
      if (same) { _toast('این وضعیت با آخرین رکورد تفاوتی ندارد.'); return; }
    }
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

  Future<void> _persistClips(List<Map<String, dynamic>> rows) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('raad.clips.v2', rows.map(jsonEncode).toList());
  }

  Future<void> _addClip() async {
    final url = await showDialog<String>(context: context, builder: (_) => const _AddClipDialog());
    if (url == null || url.isEmpty) return;
    final parsed = Uri.tryParse(url);
    if (parsed == null || !parsed.hasAuthority || !const {'https', 'http'}.contains(parsed.scheme)) {
      _toast('لینک معتبر HTTP یا HTTPS وارد کن.'); return;
    }
    if (_clips.any((clip) => clip['type'] == 'link' && clip['url'] == url)) {
      _toast('این لینک از قبل ذخیره شده.'); return;
    }
    final row = <String, dynamic>{
      'type': 'link', 'url': url, 'title': url, 'description': '',
      'created_at': DateTime.now().toIso8601String(),
    };
    final next = [row, ..._clips];
    await _persistClips(next);
    if (!mounted) return;
    setState(() => _clips = next);
    await _recordEvent('لینک کلیپ محلی ذخیره شد.');
  }

  Future<void> _pickVideo() async {
    try {
      final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (picked == null) return;
      final source = File(picked.path);
      if (!await source.exists()) { _toast('فایل ویدیو در دسترس نیست.'); return; }
      final length = await source.length();
      if (length <= 0 || length > 500 * 1024 * 1024) {
        _toast('اندازهٔ ویدیو معتبر نیست یا از سقف ۵۰۰ مگابایت بیشتر است.'); return;
      }
      final appDir = await getApplicationDocumentsDirectory();
      final clipDir = Directory('${appDir.path}/raad_clips');
      await clipDir.create(recursive: true);
      final ext = picked.name.contains('.') ? '.${picked.name.split('.').last}' : '.mp4';
      final targetPath = '${clipDir.path}/clip_${DateTime.now().millisecondsSinceEpoch}$ext';
      await source.copy(targetPath);
      if (!mounted) {
        await File(targetPath).delete().catchError((_) => File(targetPath));
        return;
      }
      final meta = await showDialog<Map<String, String>>(
        context: context,
        builder: (_) => _EditClipDialog(initialTitle: picked.name, initialDescription: ''),
      );
      if (meta == null) {
        await File(targetPath).delete().catchError((_) => File(targetPath));
        return;
      }
      final row = <String, dynamic>{
        'type': 'video', 'path': targetPath,
        'title': meta['title']!.trim().isEmpty ? picked.name : meta['title']!.trim(),
        'description': meta['description']!.trim(),
        'created_at': DateTime.now().toIso8601String(), 'size_bytes': length,
      };
      final next = [row, ..._clips];
      await _persistClips(next);
      if (!mounted) return;
      setState(() => _clips = next);
      await _recordEvent('ویدیو از گالری به حافظهٔ خصوصی برنامه وارد شد.');
      _toast('ویدیو روی همین گوشی ذخیره شد. این نسخه آپلود ابری ندارد.');
    } catch (e) {
      _toast('واردکردن ویدیو ناموفق بود؛ اجازهٔ دسترسی به گالری و فضای خالی را بررسی کن.');
    }
  }

  Future<void> _editClip(Map<String, dynamic> clip) async {
    final meta = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _EditClipDialog(
        initialTitle: clip['title']?.toString() ?? '',
        initialDescription: clip['description']?.toString() ?? '',
      ),
    );
    if (meta == null) return;
    final index = _clips.indexOf(clip);
    if (index < 0) return;
    final updated = Map<String, dynamic>.from(clip)
      ..['title'] = meta['title']!.trim()
      ..['description'] = meta['description']!.trim();
    final next = List<Map<String, dynamic>>.from(_clips);
    next[index] = updated;
    await _persistClips(next);
    if (mounted) setState(() => _clips = next);
  }

  Future<void> _removeClip(Map<String, dynamic> clip) async {
    final next = _clips.where((item) => !identical(item, clip)).toList();
    if (clip['type'] == 'video' && clip['path'] is String) {
      try { final file = File(clip['path'] as String); if (await file.exists()) await file.delete(); } catch (_) {}
    }
    await _persistClips(next);
    if (mounted) setState(() => _clips = next);
  }

  Future<void> _openClipEntry(Map<String, dynamic> clip) async {
    if (clip['type'] == 'video') {
      final path = clip['path']?.toString() ?? '';
      if (path.isEmpty || !await File(path).exists()) { _toast('فایل ویدیو پیدا نشد.'); return; }
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ClipPreviewPage(path: path, title: clip['title']?.toString() ?? 'پیش‌نمایش کلیپ'),
      ));
      return;
    }
    await _openClip(clip['url']?.toString() ?? '');
  }

  Future<void> _openClip(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasAuthority ||
        !const {'http', 'https'}.contains(uri.scheme)) {
      _toast('لینک ذخیره‌شده معتبر نیست.');
      return;
    }
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) _toast('بازکردن لینک ناموفق بود؛ مرورگر پیش‌فرض را بررسی کن.');
    } catch (_) {
      _toast('بازکردن لینک انجام نشد. برنامهٔ مرورگر را بررسی کن.');
    }
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

  Future<void> _editManualProfile() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _ManualProfileDialog(initial: _manualProfile),
    );
    if (result == null) return;
    final next = <String, dynamic>{};
    result.forEach((key, value) { if (value.trim().isNotEmpty) next[key] = value.trim(); });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('raad.manualProfile.v1', jsonEncode(next));
    if (!mounted) return;
    setState(() => _manualProfile = next);
    await _recordEvent('اطلاعات دستی پروفایل به‌روزرسانی شد.');
  }

  Future<void> _signInWithGoogle() async {
    if (googleServerClientId.trim().isEmpty) {
      _toast('ورود گوگل هنوز پیکربندی نشده است؛ شناسهٔ OAuth پروژه لازم است.');
      return;
    }
    try {
      final account = await GoogleSignIn(
        serverClientId: googleServerClientId,
        scopes: const ['email'],
      ).signIn();
      if (account == null) return;
      if (!mounted) return;
      setState(() => _googleUser = account);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('raad.googleEmail.v1', account.email);
      _toast('ورود به رعد انجام شد. برای پروفایل کالاف، نام داخل بازی یا UID را هم ثبت کن.');
    } catch (_) {
      _toast('ورود گوگل انجام نشد؛ تنظیمات OAuth و SHA-1 برنامه را بررسی کن.');
    }
  }

  Future<void> _signOutGoogle() async {
    try { await GoogleSignIn(serverClientId: googleServerClientId).signOut(); } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('raad.googleEmail.v1');
    if (mounted) setState(() => _googleUser = null);
  }

  Future<void> _checkForUpdates() async {
    if (!mounted) return;
    setState(() { _checkingUpdate = true; _updateMessage = null; });
    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/Amirho33ein7/RAAD/releases/latest'),
        headers: const {'Accept': 'application/vnd.github+json', 'User-Agent': 'RAAD-Android'},
      ).timeout(const Duration(seconds: 12));
      if (response.statusCode == 404) {
        if (mounted) setState(() { _latestTag = null; _updateApkUrl = null; _updateMessage = 'هنوز نسخه‌ای در بخش Releases منتشر نشده است.'; });
        return;
      }
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) throw const FormatException('Invalid release JSON');
      final tag = decoded['tag_name']?.toString() ?? '';
      final assets = decoded['assets'];
      String? apkUrl;
      if (assets is List) {
        for (final asset in assets) {
          if (asset is Map && asset['name']?.toString().toLowerCase().endsWith('.apk') == true) {
            apkUrl = asset['browser_download_url']?.toString();
            break;
          }
        }
      }
      if (mounted) {
        setState(() {
          _latestTag = tag;
          _updateApkUrl = apkUrl;
          _updateMessage = apkUrl == null
              ? 'نسخهٔ منتشرشده فایل APK پیوست‌شده ندارد.'
              : (_isNewerVersion(tag, raadAppVersion) ? 'نسخهٔ جدید موجود است: $tag' : 'نسخهٔ نصب‌شده به‌روز است ($raadAppVersion).');
        });
      }
    } catch (_) {
      if (mounted) setState(() => _updateMessage = 'بررسی آپدیت ناموفق بود؛ اتصال اینترنت یا محدودیت GitHub را بررسی کن.');
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  bool _isNewerVersion(String remoteTag, String localVersion) {
    List<int> parse(String value) => value.replaceFirst(RegExp(r'^[vV]'), '').split('+').first
        .split('.').map((part) => int.tryParse(part) ?? 0).toList();
    final remote = parse(remoteTag), local = parse(localVersion);
    for (var i = 0; i < (remote.length > local.length ? remote.length : local.length); i++) {
      final a = i < remote.length ? remote[i] : 0;
      final b = i < local.length ? local[i] : 0;
      if (a != b) return a > b;
    }
    return false;
  }

  Future<void> _openUpdateDownload() async {
    final url = _updateApkUrl;
    if (url == null) { _toast('لینک APK نسخهٔ جدید موجود نیست.'); return; }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host != 'github.com') { _toast('نشانی دانلود معتبر نیست.'); return; }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _toast('بازکردن لینک دانلود ناموفق بود.');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
  void _go(int page) {
    Navigator.pop(context);
    setState(() => _page = page);
    if (page == 7) _checkForUpdates();
  }

  @override
  void dispose() {
    _query.dispose();
    _compareQuery.dispose();
    _profileService.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl, child: PopScope<void>(
    canPop: _page == 0,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && _page != 0 && mounted) setState(() => _page = 0);
    },
    child: Scaffold(
    appBar: AppBar(title: const Text('رعد ⚡', style: TextStyle(fontWeight: FontWeight.bold)),
      actions: [IconButton(icon: const Icon(Icons.info_outline), tooltip: 'دربارهٔ رعد', onPressed: () => showAboutDialog(
        context: context, applicationName: 'رعد | RAAD', applicationVersion: '0.2.0',
        children: const [Text('اپ مستقل و غیررسمی برای نمایش فیلدهای قابل‌دسترسی پروفایل CODM.'), Text('رمز عبور بازی درخواست نمی‌شود.')]))]),
    drawer: Drawer(child: SafeArea(child: ListView(padding: EdgeInsets.zero, children: [
      const Padding(padding: EdgeInsets.all(20), child: Text('رَعد | RAAD\nنبض رنک، زیر نظر تو', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
      const Divider(),
      _nav(Icons.dashboard_outlined, 'داشبورد', 0),
      _nav(Icons.person_search_outlined, 'پروفایل کالاف', 1),
      _nav(Icons.show_chart, 'ردیاب رنک', 2),
      _nav(Icons.compare_arrows, 'مقایسهٔ بازیکنان', 3),
      _nav(Icons.video_library_outlined, 'کلیپ‌های من', 4),
      _nav(Icons.history, 'تاریخچهٔ همگام‌سازی', 5),
      _nav(Icons.settings_outlined, 'تنظیمات', 6),
      _nav(Icons.system_update_alt, 'بررسی آپدیت', 7),
      _nav(Icons.privacy_tip_outlined, 'حریم خصوصی و دربارهٔ رعد', 8),
      const SizedBox(height: 12),
      const Padding(padding: EdgeInsets.all(16), child: Text('رکوردها و لینک‌ها محلی هستند. سرور پروفایل، غیررسمی است.', style: TextStyle(color: Colors.white60, fontSize: 12))),
    ]))),
    body: SafeArea(child: AnimatedSwitcher(duration: const Duration(milliseconds: 180),
      child: KeyedSubtree(key: ValueKey<int>(_page), child: _body()))),
  )));

  Widget _body() {
    switch (_page) {
      case 1: return _profilePage();
      case 2: return _rankPage();
      case 3: return _comparePage();
      case 4: return _clipsPage();
      case 5: return _eventsPage();
      case 6: return _settingsPage();
      case 7: return _updatesPage();
      case 8: return _privacyPage();
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
    _action(Icons.video_library_outlined, 'کلیپ‌های من', _clips.length.toString() + ' مورد ذخیره‌شده', () => setState(() => _page = 4)),
    _action(Icons.person_outline, 'پروفایل من', 'نمایش داده‌های دریافت‌شده و ویرایش مقادیر ناموجود', () => setState(() => _page = 1)),
    _action(Icons.system_update_alt, 'بررسی آپدیت', 'نسخهٔ جدید از GitHub Releases', () { setState(() => _page = 7); _checkForUpdates(); }),
    const SizedBox(height: 12),
    _accountCard(),
    if (_displayProfile != null) ...[const SizedBox(height: 16), _heading('آخرین پروفایل'), _profileCard(_displayProfile!)],
    const SizedBox(height: 12),
    _notice('حریم خصوصی', 'رمز عبور بازی را وارد نکن. تاریخچه و لینک‌ها روی همین دستگاه ذخیره می‌شوند.'),
  ]);

  Widget _profilePage() => ListView(padding: const EdgeInsets.all(18), children: [
    _heading('جست‌وجوی پروفایل'),
    const SizedBox(height: 8),
    const Text('برای پیدا کردن پروفایل، نام دقیق داخل بازی یا UID را وارد کن. ورود Gmail به‌تنهایی اکانت کالاف را به API وصل نمی‌کند.', style: TextStyle(color: Colors.white60)),
    const SizedBox(height: 12),
    TextField(controller: _query, textDirection: TextDirection.ltr, onSubmitted: (_) => _search(),
      decoration: InputDecoration(hintText: 'نام بازیکن یا شناسه', prefixIcon: const Icon(Icons.search),
        filled: true, fillColor: panel, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none))),
    const SizedBox(height: 10),
    FilledButton.icon(onPressed: _loading ? null : _search,
      icon: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.cloud_download_outlined),
      label: Text(_loading ? 'در حال دریافت…' : 'دریافت پروفایل')),
    if (_error != null) ...[const SizedBox(height: 10), _notice('دریافت ناموفق بود', _error!, color: Colors.redAccent)],
    const SizedBox(height: 12),
    OutlinedButton.icon(onPressed: _editManualProfile, icon: const Icon(Icons.edit_outlined), label: const Text('ویرایش دستی پروفایل و رنک')),
    if (_displayProfile != null) ...[
      const SizedBox(height: 18), _heading('اطلاعات پروفایل'), _profileCard(_displayProfile!),
      ..._profileImages(_displayProfile!),
      ..._profileFields(_displayProfile!),
      const SizedBox(height: 8),
      FilledButton.tonalIcon(onPressed: _saveSnapshot, icon: const Icon(Icons.bookmark_add_outlined), label: const Text('ذخیرهٔ رکورد رنک')),
      const SizedBox(height: 10),
      if (_manualProfile.isNotEmpty) _notice('مقادیر دستی', 'برخی فیلدها با اطلاعاتی که خودت وارد کرده‌ای جایگزین شده‌اند؛ برای مقادیر دستی برچسب منبع نمایش داده می‌شود.'),
      _notice('محدودیت داده‌ها', 'سرویس شخص ثالث غیررسمی است و فقط داده‌های موجود در پاسخ آن نمایش داده می‌شود. آمار مسابقات یا کیل/دث ساخته نمی‌شود.'),
    ] else _empty(Icons.person_search_outlined, 'پروفایلی ثبت نشده', 'نام یا UID بازیکن را بالا وارد کن، یا اطلاعاتی را که می‌دانی به‌صورت دستی ذخیره کن.'),
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
    const Text('پروفایل اول از بخش پروفایل یا اطلاعات دستی گرفته می‌شود. سپس بازیکن دوم را با نام یا UID جست‌وجو کن.', style: TextStyle(color: Colors.white60)),
    const SizedBox(height: 12),
    if (_displayProfile == null)
      _action(Icons.person_search, 'پروفایل اول را ثبت کن', 'رفتن به بخش پروفایل', () => setState(() => _page = 1))
    else _profileCard(_displayProfile!),
    const SizedBox(height: 12),
    TextField(controller: _compareQuery, textDirection: TextDirection.ltr, onSubmitted: (_) => _compare(),
      decoration: InputDecoration(hintText: 'شناسه یا نام بازیکن دوم', prefixIcon: const Icon(Icons.compare_arrows),
        filled: true, fillColor: panel, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none))),
    const SizedBox(height: 10),
    FilledButton.icon(onPressed: _compareLoading ? null : _compare,
      icon: _compareLoading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.compare),
      label: Text(_compareLoading ? 'در حال دریافت…' : 'دریافت و مقایسه')),
    if (_compareError != null) ...[const SizedBox(height: 10), _notice('خطا در مقایسه', _compareError!, color: Colors.redAccent)],
    if (_displayProfile != null && _otherProfile != null) ...[
      const SizedBox(height: 16),
      Row(children: [Expanded(child: _playerHeader(_displayProfile!)), const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.compare_arrows, color: accent)), Expanded(child: _playerHeader(_otherProfile!))]),
      const SizedBox(height: 10),
      _compareRow('لول', _displayProfile!['level'], _otherProfile!['level']),
      _compareRow('امتیاز رنک', _displayProfile!['rating'], _otherProfile!['rating']),
      _compareRow('رنک مولتی‌پلیر', _displayProfile!['customReadableMpRank'], _otherProfile!['customReadableMpRank']),
      _compareRow('کشور', _displayProfile!['country'], _otherProfile!['country']),
      _notice('نحوهٔ مقایسه', 'مقادیر دستی پروفایل اول با برچسب دستی در رعد ذخیره می‌شوند. اختلاف عددی فقط زمانی محاسبه می‌شود که هر دو مقدار عددی و موجود باشند.'),
    ],
  ]);

  Widget _clipsPage() => ListView(padding: const EdgeInsets.all(18), children: [
    _heading('کلیپ‌های من'),
    const SizedBox(height: 8),
    const Text('می‌توانی ویدیو را از گالری وارد کنی یا لینک کلیپ اضافه کنی. فایل‌های ویدیویی فعلاً به‌صورت محلی و خصوصی روی همین گوشی ذخیره می‌شوند؛ فضای ابری فعال نیست.', style: TextStyle(color: Colors.white60)),
    const SizedBox(height: 12),
    FilledButton.icon(onPressed: _pickVideo, icon: const Icon(Icons.video_library_outlined), label: const Text('انتخاب ویدیو از گالری')),
    const SizedBox(height: 8),
    OutlinedButton.icon(onPressed: _addClip, icon: const Icon(Icons.add_link), label: const Text('افزودن لینک کلیپ')),
    const SizedBox(height: 10),
    if (_clips.isEmpty) _empty(Icons.video_library_outlined, 'کتابخانه خالی است', 'یک ویدیو از گالری انتخاب کن یا لینک اضافه کن.'),
    ..._clips.map((clip) => Card(color: panel, child: ListTile(
      leading: Icon(clip['type'] == 'video' ? Icons.movie_outlined : Icons.link, color: accent),
      title: Text(clip['title']?.toString().isNotEmpty == true ? clip['title'].toString() : 'کلیپ بدون عنوان'),
      subtitle: Text([
        if ((clip['description']?.toString() ?? '').isNotEmpty) clip['description'].toString(),
        clip['type'] == 'video' ? 'فایل ذخیره‌شده روی گوشی' : 'لینک ذخیره‌شده روی دستگاه',
      ].join(' • ')),
      onTap: () => _openClipEntry(clip),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(tooltip: 'حذف', onPressed: () => _removeClip(clip), icon: const Icon(Icons.delete_outline)),
        PopupMenuButton<String>(
        tooltip: 'عملیات کلیپ',
        onSelected: (value) {
          if (value == 'open') _openClipEntry(clip);
          if (value == 'edit') _editClip(clip);
          if (value == 'delete') _removeClip(clip);
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'open', child: Text('پخش / بازکردن')),
          PopupMenuItem(value: 'edit', child: Text('ویرایش عنوان و توضیح')),
          PopupMenuItem(value: 'delete', child: Text('حذف')),
        ],
      ),
      ]),
    ))),
  ]);

  Widget _settingsPage() => ListView(padding: const EdgeInsets.all(18), children: [
    _heading('تنظیمات'),
    const SizedBox(height: 12),
    _accountCard(),
    const SizedBox(height: 12),
    _action(Icons.edit_note_outlined, 'اطلاعات دستی پروفایل', 'ثبت یا اصلاح لول، رنک و امتیاز ناموجود', _editManualProfile),
    const SizedBox(height: 12),
    _notice('اتصال کالاف', 'رعد از سرویس عمومی و غیررسمی برای جست‌وجوی نام یا UID استفاده می‌کند. ورود Google فقط ورود به رعد است و دسترسی خصوصی به اطلاعات Activision ایجاد نمی‌کند.'),
  ]);

  Widget _updatesPage() => ListView(padding: const EdgeInsets.all(18), children: [
    _heading('بررسی آپدیت رعد'),
    const SizedBox(height: 8),
    _notice('نسخهٔ نصب‌شده', raadAppVersion),
    const SizedBox(height: 12),
    if (_checkingUpdate) const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
    if (_updateMessage != null) _notice('وضعیت آپدیت', _updateMessage!, color: _updateApkUrl != null && _isNewerVersion(_latestTag ?? '', raadAppVersion) ? accent : Colors.white70)
    else const Text('برای بررسی آخرین نسخه، دکمهٔ زیر را بزن.', style: TextStyle(color: Colors.white60)),
    const SizedBox(height: 12),
    FilledButton.icon(onPressed: _checkingUpdate ? null : () => _checkForUpdates(),
      icon: const Icon(Icons.refresh), label: const Text('بررسی دوبارهٔ نسخهٔ جدید')),
    if (_updateApkUrl != null && _isNewerVersion(_latestTag ?? '', raadAppVersion)) ...[
      const SizedBox(height: 8),
      FilledButton.icon(onPressed: _openUpdateDownload, icon: const Icon(Icons.download), label: const Text('دانلود APK جدید از GitHub')),
    ],
    const SizedBox(height: 8),
    TextButton.icon(onPressed: () => launchUrl(Uri.parse(githubReleasesPage), mode: LaunchMode.externalApplication),
      icon: const Icon(Icons.open_in_new), label: const Text('مشاهدهٔ همهٔ نسخه‌ها در GitHub')),
    const SizedBox(height: 8),
    _notice('روش انتشار', 'نسخهٔ جدید زمانی در این صفحه دیده می‌شود که صاحب پروژه یک نسخهٔ GitHub Release با تگ نسخه و فایل APK منتشر کند.'),
  ]);

  Widget _privacyPage() => ListView(padding: const EdgeInsets.all(18), children: [
    _heading('حریم خصوصی و دربارهٔ رعد'),
    const SizedBox(height: 12),
    _notice('پروژهٔ مستقل', 'رعد محصول رسمی Activision نیست و سرویس پروفایل استفاده‌شده غیررسمی است.'),
    const SizedBox(height: 8),
    _notice('داده‌های محلی', 'تاریخچه، مقادیر دستی پروفایل و کلیپ‌های واردشده در حافظهٔ همین گوشی ذخیره می‌شوند. در نسخهٔ فعلی، فایل ویدیو به فضای ابری ارسال نمی‌شود.'),
    const SizedBox(height: 8),
    _notice('حساب Google', 'ایمیل برای ورود به خود برنامه استفاده می‌شود، نه برای کشف خودکار پروفایل کالاف. هیچ‌وقت رمز عبور Activision یا Google را در فرم‌های داخل برنامه وارد نکن.'),
    const SizedBox(height: 12),
    TextButton.icon(onPressed: () => launchUrl(Uri.parse('https://github.com/Harry260/codm-api'), mode: LaunchMode.externalApplication),
      icon: const Icon(Icons.open_in_new), label: const Text('مستندات سرویس غیررسمی پروفایل')),
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

  List<Widget> _profileImages(Map<String, dynamic> p) {
    const imageFields = <String, String>{
      'customLevelImageUrl': 'نشان لول',
      'customMpRankImageUrl': 'نشان رنک مولتی‌پلیر',
    };
    return imageFields.entries.where((entry) {
      final url = p[entry.key]?.toString() ?? '';
      final uri = Uri.tryParse(url);
      return uri != null && uri.hasAuthority && uri.scheme == 'https';
    }).map((entry) => Card(
      color: panel,
      child: ListTile(
        leading: Image.network(
          p[entry.key].toString(),
          width: 42,
          height: 42,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported_outlined, color: Colors.white54),
        ),
        title: Text(entry.value),
      ),
    )).toList();
  }

  List<Widget> _profileFields(Map<String, dynamic> p) {
    const labels = <String, String>{
      'nickname': 'نام بازیکن', 'level': 'لول', 'customReadableMpRank': 'رنک مولتی‌پلیر',
      'rating': 'امتیاز رنک', 'rankClass': 'کد رنک دریافتی', 'shortId': 'شناسهٔ کوتاه',
      'country': 'کشور', 'countryId': 'شناسهٔ کشور',
    };
    const icons = <String, IconData>{
      'nickname': Icons.person_outline, 'level': Icons.military_tech_outlined,
      'customReadableMpRank': Icons.emoji_events_outlined, 'rating': Icons.insights_outlined,
      'rankClass': Icons.tag, 'shortId': Icons.tag, 'country': Icons.public,
      'countryId': Icons.public,
    };
    final keys = ['nickname', 'level', 'customReadableMpRank', 'rating', 'rankClass', 'shortId', 'country', 'countryId'];
    return keys.where((key) => p[key] != null && p[key].toString().trim().isNotEmpty).map((key) {
      final manual = _manualProfile.containsKey(key);
      return _field((labels[key] ?? key) + (manual ? ' • ثبت دستی' : ''), _display(p[key]), icons[key] ?? Icons.info_outline);
    }).toList();
  }

  Widget _accountCard() => Card(color: panel, child: ListTile(
    leading: const CircleAvatar(backgroundColor: Color(0xFF173747), child: Icon(Icons.account_circle_outlined, color: accent)),
    title: Text(_googleUser == null ? 'ورود به رعد با حساب Google' : 'حساب متصل‌شده'),
    subtitle: Text(_googleUser?.email ?? 'برای فعال‌شدن ورود، OAuth گوگل باید تنظیم شود. این ورود به‌خودی‌خود کالاف را متصل نمی‌کند.'),
    trailing: IconButton(
      tooltip: _googleUser == null ? 'ورود با گوگل' : 'خروج از حساب',
      icon: Icon(_googleUser == null ? Icons.login : Icons.logout),
      onPressed: _googleUser == null ? _signInWithGoogle : _signOutGoogle,
    ),
  ));

  Widget _profileCard(Map<String, dynamic> p) => Card(color: panel, child: ListTile(
    leading: _avatar(p['picUrl']?.toString()),
    title: Text(_value(p, 'nickname')),
    subtitle: Text('لول: ' + _value(p, 'level') + ' • رنک: ' + _value(p, 'customReadableMpRank'))));

  Widget _avatar(String? url) {
    if (url == null || url.trim().isEmpty) {
      return const CircleAvatar(backgroundColor: Color(0xFF173747), child: Icon(Icons.person_outline, color: accent));
    }
    return CircleAvatar(backgroundColor: const Color(0xFF173747), child: ClipOval(
      child: Image.network(url, width: 44, height: 44, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.person_outline, color: accent)),
    ));
  }

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


/// The dialog owns its controller so it remains alive throughout the route's
/// reverse transition instead of being disposed immediately after Navigator.pop.
class _AddClipDialog extends StatefulWidget {
  const _AddClipDialog();

  @override
  State<_AddClipDialog> createState() => _AddClipDialogState();
}

class _AddClipDialogState extends State<_AddClipDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('افزودن لینک کلیپ'),
        content: TextField(
          controller: _controller,
          autofocus: true,
          textDirection: TextDirection.ltr,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: 'https://...'),
          onSubmitted: (_) => Navigator.of(context).pop(_controller.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
            child: const Text('ذخیره'),
          ),
        ],
      );
}


class _EditClipDialog extends StatefulWidget {
  const _EditClipDialog({required this.initialTitle, required this.initialDescription});

  final String initialTitle;
  final String initialDescription;

  @override
  State<_EditClipDialog> createState() => _EditClipDialogState();
}

class _EditClipDialogState extends State<_EditClipDialog> {
  late final TextEditingController _title = TextEditingController(text: widget.initialTitle);
  late final TextEditingController _description = TextEditingController(text: widget.initialDescription);

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('اطلاعات کلیپ'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: _title, autofocus: true, decoration: const InputDecoration(labelText: 'عنوان کلیپ')),
            const SizedBox(height: 8),
            TextField(controller: _description, minLines: 2, maxLines: 4,
              decoration: const InputDecoration(labelText: 'توضیحات (اختیاری)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(),
            child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.of(context).pop({
            'title': _title.text, 'description': _description.text,
          }), child: const Text('ذخیره')),
        ],
      );
}

class _ManualProfileDialog extends StatefulWidget {
  const _ManualProfileDialog({required this.initial});

  final Map<String, dynamic> initial;

  @override
  State<_ManualProfileDialog> createState() => _ManualProfileDialogState();
}

class _ManualProfileDialogState extends State<_ManualProfileDialog> {
  late final TextEditingController _nickname = TextEditingController(text: widget.initial['nickname']?.toString() ?? '');
  late final TextEditingController _level = TextEditingController(text: widget.initial['level']?.toString() ?? '');
  late final TextEditingController _rank = TextEditingController(text: widget.initial['customReadableMpRank']?.toString() ?? '');
  late final TextEditingController _rating = TextEditingController(text: widget.initial['rating']?.toString() ?? '');
  late final TextEditingController _shortId = TextEditingController(text: widget.initial['shortId']?.toString() ?? '');
  late final TextEditingController _country = TextEditingController(text: widget.initial['country']?.toString() ?? '');

  @override
  void dispose() {
    _nickname.dispose();
    _level.dispose();
    _rank.dispose();
    _rating.dispose();
    _shortId.dispose();
    _country.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('ویرایش دستی پروفایل'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('فقط مقادیری را وارد کن که خودت می‌دانی. این موارد با برچسب ثبت دستی نمایش داده می‌شوند و دادهٔ دریافت‌شده از API محسوب نمی‌شوند.'),
            const SizedBox(height: 12),
            TextField(controller: _nickname, decoration: const InputDecoration(labelText: 'نام داخل بازی')),
            TextField(controller: _level, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'لول')),
            TextField(controller: _rank, decoration: const InputDecoration(labelText: 'رنک مولتی‌پلیر')),
            TextField(controller: _rating, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'امتیاز رنک')),
            TextField(controller: _shortId, decoration: const InputDecoration(labelText: 'شناسهٔ کوتاه')),
            TextField(controller: _country, decoration: const InputDecoration(labelText: 'کد کشور (اختیاری)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(),
            child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.of(context).pop(<String, String>{}),
            child: const Text('پاک‌کردن مقادیر دستی')),
          FilledButton(onPressed: () => Navigator.of(context).pop(<String, String>{
            'nickname': _nickname.text,
            'level': _level.text,
            'customReadableMpRank': _rank.text,
            'rating': _rating.text,
            'shortId': _shortId.text,
            'country': _country.text,
          }), child: const Text('ذخیره')),
        ],
      );
}

class ClipPreviewPage extends StatefulWidget {
  const ClipPreviewPage({super.key, required this.path, required this.title});

  final String path;
  final String title;

  @override
  State<ClipPreviewPage> createState() => _ClipPreviewPageState();
}

class _ClipPreviewPageState extends State<ClipPreviewPage> {
  late final VideoPlayerController _controller = VideoPlayerController.file(File(widget.path));
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.initialize().then((_) {
      if (mounted) setState(() {});
    }).catchError((Object _) {
      if (mounted) setState(() => _error = 'پخش این فرمت ویدیو در دستگاه ممکن نیست.');
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: Text(widget.title)),
          body: Center(
            child: _error != null
                ? Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center))
                : !_controller.value.isInitialized
                    ? const CircularProgressIndicator()
                    : Column(mainAxisSize: MainAxisSize.min, children: [
                        AspectRatio(
                          aspectRatio: _controller.value.aspectRatio > 0 ? _controller.value.aspectRatio : 16 / 9,
                          child: VideoPlayer(_controller),
                        ),
                        const SizedBox(height: 12),
                        IconButton.filled(
                          iconSize: 34,
                          onPressed: () {
                            setState(() {
                              _controller.value.isPlaying ? _controller.pause() : _controller.play();
                            });
                          },
                          icon: Icon(_controller.value.isPlaying ? Icons.pause : Icons.play_arrow),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: VideoProgressIndicator(_controller, allowScrubbing: true),
                        ),
                      ]),
          ),
        ),
      );
}
