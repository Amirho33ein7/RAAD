# رَعد | RAAD

**شعار:** نبض رنک، زیر نظر تو ⚡

رعد یک اپ مستقل، فارسی و راست‌چین برای نمایش داده‌های قابل‌دسترسی پروفایل Call of Duty: Mobile است. این اپ محصول رسمی Activision نیست.

## قابلیت‌های نسخهٔ 0.3.0

- **پروفایل بازیکن:** جست‌وجو با نام یا UID؛ پشتیبانی از ساختار تخت و ساختار تو‌در‌توی پاسخ سرویس غیررسمی و نمایش فیلدهای واقعی شناخته‌شده مثل نام، لول، رنک، امتیاز، شناسه و کشور.
- **ویرایش دستی پروفایل:** اگر سرویس مقداری را برنگرداند، کاربر می‌تواند داده‌ای را که خودش می‌داند وارد کند. فیلدهای دستی از داده‌های API متمایز می‌مانند.
- **ردیاب رنک:** نگه‌داری تا ۵۰ رکورد محلی، همراه زمان ثبت و جلوگیری از ذخیرهٔ رکورد یکسان با آخرین وضعیت.
- **مقایسهٔ بازیکنان:** مقایسهٔ فیلدهای واقعی دو پروفایل؛ اختلاف عددی فقط برای مقادیر عددی موجود محاسبه می‌شود.
- **کلیپ‌ها:** انتخاب فایل ویدیو از گالری، کپی به فضای خصوصی برنامه، پخش ویدیو، تغییر عنوان/توضیح، حذف فایل و نگه‌داری لینک‌ها. فایل ویدیو در این نسخه روی همین گوشی ذخیره می‌شود؛ Firebase Storage یا آپلود ابری فعال نیست.
- **ورود اختیاری Google:** مسیر ورود با Google آماده است، اما تا زمان اضافه‌کردن OAuth Client ID و امضای پایدار اندروید کار نمی‌کند. این ورود به‌خودی‌خود پروفایل کالاف را پیدا یا به Activision متصل نمی‌کند.
- **بررسی آپدیت:** صفحهٔ آپدیت آخرین GitHub Release را بررسی می‌کند و اگر نسخهٔ جدیدتر همراه فایل APK منتشر شده باشد، لینک دانلود همان APK را باز می‌کند.
- **بازگشت اندروید:** دکمهٔ Back از زیرصفحه‌ها به داشبورد برمی‌گردد.

آمار کیل/دث، تاریخچهٔ مسابقات، K/D یا فیلدهایی که سرویس در پاسخ ندارد ساخته نمی‌شوند.

## دریافت APK آزمایشی

برای دریافت build ساخته‌شده توسط GitHub Actions، بخش [Actions مخزن](https://github.com/Amirho33ein7/RAAD/actions) را باز کن، اجرای موفق **Build RAAD Android APK** را انتخاب و artifact با نام `raad-android-apk` را دانلود کن. Artifactهای Actions موقتی‌اند و ۱۴ روز نگه‌داری می‌شوند.

## انتشار APK قابل دریافت از داخل برنامه

فایل `.github/workflows/release-android.yml` با دو روش اجرا می‌شود:
1. در GitHub به Actions برو، workflow **Publish RAAD Android Release** را انتخاب کن و **Run workflow** را با تگ نسخه مانند `v0.3.0` اجرا کن.
2. یا یک تگ به شکل `v*` روی commit انتشار push کن.

پس از موفقیت تست‌ها و ساخت، workflow فایل `app-release.apk` را به GitHub Releases وصل می‌کند. صفحهٔ آپدیت داخل برنامه آخرین Release را می‌خواند و فقط وقتی از نسخهٔ نصب‌شده جدیدتر باشد، دانلود APK را پیشنهاد می‌کند. به‌روزرسانی خودکار/بی‌صدا انجام نمی‌شود؛ Android دانلود و نصب را به کاربر می‌سپارد.

## پیکربندی ورود Google

این مخزن عمداً هیچ OAuth ID، فایل `google-services.json`، کلید امضا یا رمز محرمانه‌ای ندارد. برای فعال‌کردن ورود Google:

1. در Google Cloud Console برای نام بستهٔ `com.raad.mobile` کلاینت‌های OAuth اندروید و وب را با پیکربندی صحیح بساز.
2. از یک کلید امضای اندروید پایدار برای buildهای انتشار استفاده کن؛ SHA-1 باید با کلاینت Android مطابقت داشته باشد.
3. شناسهٔ OAuth کلاینت وب را به‌عنوان GitHub Actions repository secret با نام `RAAD_GOOGLE_SERVER_CLIENT_ID` ثبت کن.
4. workflow ساخت/انتشار را دوباره اجرا کن.

بدون تنظیم این موارد، دکمهٔ ورود پیام واضح می‌دهد و وانمود نمی‌کند کاربر وارد شده است. برای احراز هویت ابری و همگام‌سازی داده‌های کاربران به Firebase Authentication/Backend هم نیاز است؛ این بخش هنوز در این نسخه فعال نیست.

## اجرای اپ با Flutter

نیاز به Flutter SDK و Android SDK است. از پوشهٔ مخزن:

    cd app
    flutter create --platforms=android --org com.raad.mobile --project-name raad .
    flutter pub get
    flutter analyze
    flutter test
    flutter run

حالت پیش‌فرض موبایل از API شخص ثالث و غیررسمی استفاده می‌کند؛ دسترس‌پذیری آن تضمین‌شده نیست. مستندات: https://github.com/Harry260/codm-api

## اجرای Backend (اختیاری)

اگر Backend را روی یک میزبان HTTPS خودت اجرا کرده‌ای:

    cd backend
    python -m venv .venv
    # Windows: .venv\\Scripts\\activate
    # macOS/Linux: source .venv/bin/activate
    pip install -r requirements-dev.txt
    uvicorn app.main:app --reload

مستندات API محلی در http://127.0.0.1:8000/docs و وضعیت سرور در /health دیده می‌شوند. اجرای اپ با Backend:

    cd app
    flutter run --dart-define=RAAD_USE_BACKEND=true --dart-define=RAAD_API_URL=https://YOUR-HOST

مسیرهای پشتیبانی‌شده: `GET /health`، `GET /api/v1/capabilities` و `GET /api/v1/codm/profile?q=<nickname-or-uid>`. Backend فعلی بدون PostgreSQL اجرا می‌شود؛ cache آن موقت و درون‌حافظه‌ای است و تاریخچهٔ رنک محلی می‌ماند.

## تست‌ها

Backend:

    cd backend
    pip install -r requirements-dev.txt
    PYTHONPATH=. python -m pytest -q

اپ Flutter: workflow اندروید `flutter analyze` و `flutter test` را پیش از ساخت APK اجرا می‌کند.

پروفایل‌های جست‌وجوشده نیز به‌صورت محلی روی دستگاه ذخیره می‌شوند؛ گزینهٔ ذخیره شناسه یا عبارت جست‌وجو را نگه می‌دارد تا پروفایل بعداً بدون درخواست شبکه دوباره باز شود.

## حریم خصوصی و محدودیت‌ها

- رعد رمز عبور Google یا Activision را درخواست نمی‌کند.
- API پروفایل غیررسمی است، ممکن است قطع شود و فقط فیلدهای موجود را می‌تواند برگرداند.
- اطلاعات دستی، رکوردهای رنک و کلیپ‌های واردشده در فضای محلی برنامه می‌مانند. حذف برنامه یا پاک‌کردن داده‌های آن ممکن است این اطلاعات را حذف کند.
- آپلود ابری ویدیو، Firebase Authentication، Firebase Storage و PostgreSQL هنوز راه‌اندازی نشده‌اند.
- برای انتشار عمومی، OAuth و امضای ثابت Android را قبل از انتشار تنظیم کن. هیچ کلید خصوصی یا فایل حاوی رمز را commit نکن.

## فناوری‌ها

Flutter / Dart · SharedPreferences · image_picker · video_player · path_provider · Google Sign-In (OAuth configuration required) · Python / FastAPI · httpx · pytest · GitHub Actions

Call of Duty: Mobile و Activision متعلق به صاحبان مربوطه هستند. رعد یک پروژهٔ مستقل و غیررسمی است.
