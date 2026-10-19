# رَعد | RAAD

**شعار:** نبض رنک، زیر نظر تو ⚡

رعد یک اپ همراه فارسی و راست‌چین برای نمایش اطلاعات قابل‌دسترسی پروفایل Call of Duty: Mobile است. این پروژه مستقل و غیررسمی است و ادعای وابستگی یا تأیید Activision را ندارد.

## چه چیزهایی الان پیاده‌سازی شده‌اند؟

- **پروفایل بازیکن:** جست‌وجو با نام یا شناسه و نمایش فقط فیلدهای موجود در پاسخ API.
- **ردیاب رنک محلی:** ذخیره تا ۵۰ snapshot روی دستگاه، با زمان ثبت و فیلدهای واقعی دریافت‌شده.
- **مقایسهٔ پروفایل‌ها:** نمایش مقادیر مشترک برای دو پروفایل؛ اختلاف عددی فقط وقتی هر دو مقدار عددی موجود باشند محاسبه می‌شود.
- **کلیپ‌های من:** ذخیره و حذف لینک‌های HTTP/HTTPS در حافظهٔ محلی برنامه. آپلود ویدیو یا فضای ابری هنوز متصل نیست.
- **تاریخچهٔ رخدادها:** ثبت محلی نتیجهٔ جست‌وجو و ذخیره‌سازی.
- **Backend FastAPI:** endpoint سلامت، endpoint قابلیت‌ها و پروکسی اختیاری پروفایل با timeout، پیام خطا و cache کوتاه‌مدت.
- **بررسی خودکار:** workflow برای تحلیل Dart، اجرای تست Flutter و ساخت APK اندروید.

هیچ آمار کیل/دث، تاریخچهٔ مسابقات یا موجودی کامل آیتم‌ها جعل نمی‌شود. فقط فیلدهایی که سرویس واقعاً برمی‌گرداند قابل نمایش‌اند.

## دریافت APK

بعد از اجرای موفق workflow ساخت اندروید، وارد بخش [Actions مخزن](https://github.com/Amirho33ein7/RAAD/actions) شو، آخرین اجرای **Build RAAD Android APK** را باز کن و artifact با نام raad-android-apk را دانلود کن. اگر workflow شکست خورده باشد، APK معتبر در artifact وجود نخواهد داشت؛ نتیجهٔ اجرا را قبل از نصب بررسی کن.

## اجرای اپ با Flutter

نیاز به Flutter SDK و Android SDK داری. چون پوشهٔ پلتفرم Android در مخزن نگه‌داری نمی‌شود، یک‌بار از داخل پوشهٔ app آن را بساز. دستورات:

    cd app
    flutter create --platforms=android --org com.raad.mobile --project-name raad .
    flutter pub get
    flutter test
    flutter run

حالت پیش‌فرض موبایل از API غیررسمی مستندشده استفاده می‌کند. پایداری و دسترس‌پذیری این سرویس تضمین‌شده نیست و ممکن است بر اساس منطقه یا محدودیت سرویس کار نکند.

## اجرای اپ از طریق Backend خودت (اختیاری)

اگر Backend را روی یک میزبان HTTPS خودت اجرا کردی، آدرس آن را هنگام اجرا مشخص کن:

    flutter run --dart-define=RAAD_USE_BACKEND=true --dart-define=RAAD_API_URL=https://YOUR-HOST

آدرس نمونه را با دامنهٔ واقعی خودت جایگزین کن. Backend از مسیرهای زیر پشتیبانی می‌کند:

- GET /health
- GET /api/v1/capabilities
- GET /api/v1/codm/profile?q=<nickname-or-uid>

## اجرای Backend

    cd backend
    python -m venv .venv
    # Windows: .venv\Scripts\activate
    # macOS/Linux: source .venv/bin/activate
    pip install -r requirements-dev.txt
    uvicorn app.main:app --reload

مستندات API محلی در http://127.0.0.1:8000/docs و وضعیت سرور در /health دیده می‌شوند. مقدار CODM_API_BASE_URL قابل تنظیم است. Backend فعلی بدون دیتابیس اجرا می‌شود و cache آن موقت و درون‌حافظه‌ای است؛ تاریخچهٔ رنک در این نسخه روی خود دستگاه نگه‌داری می‌شود.

## تست‌ها

Backend:

    cd backend
    pip install -r requirements-dev.txt
    PYTHONPATH=. python -m pytest -q

اپ Flutter با GitHub Actions بررسی می‌شود. APK نهایی تنها بعد از گذر موفق مراحل workflow قابل استفاده است.

## حریم خصوصی و محدودیت‌ها

- رعد رمز عبور حساب Activision را درخواست نمی‌کند.
- API شخص ثالث غیررسمی است، ممکن است از دسترس خارج شود، و اطلاعات کامل یا دائمی را تضمین نمی‌کند.
- تاریخچه و لینک‌های کلیپ با SharedPreferences روی همان دستگاه ذخیره می‌شوند؛ احراز هویت ابری و Firebase هنوز پیکربندی نشده‌اند.
- Backend و PostgreSQL روی سرور عمومی deploy نشده‌اند؛ برای استفاده از حالت Backend باید خودت آن را روی HTTPS میزبانی کنی.
- کلید، رمز یا فایل .env حاوی اطلاعات محرمانه را commit نکن.

## فناوری‌ها

Flutter / Dart · SharedPreferences · Python / FastAPI · httpx · pytest · GitHub Actions

Call of Duty: Mobile و Activision متعلق به صاحبان مربوطه هستند. رعد یک پروژهٔ مستقل و غیررسمی است.
