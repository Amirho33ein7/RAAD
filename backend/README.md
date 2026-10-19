# راهنمای Backend رعد

## نصب و اجرا

    python -m venv .venv
    # Windows: .venv\Scripts\activate
    # macOS/Linux: source .venv/bin/activate
    pip install -r requirements-dev.txt
    uvicorn app.main:app --reload

سرور محلی روی http://127.0.0.1:8000 اجرا می‌شود. مستندات در /docs و بررسی سلامت در /health هستند.

## مسیرهای API

- GET /health — وضعیت سرور
- GET /api/v1/capabilities — فهرست قابلیت‌های موجود و محدودیت‌ها
- GET /api/v1/codm/profile?q=<nickname-or-uid> — پروکسی کنترل‌شده برای فیلدهای پروفایل

## تنظیمات

تنظیمات نمونه در فایل .env.example آمده‌اند. ماژول از python-dotenv برای بارگذاری فایل .env استفاده می‌کند. برای تغییر ارائه‌دهنده، مقدار CODM_API_BASE_URL را تنظیم کن. فایل .env حاوی اطلاعات خصوصی را commit نکن.

## تست

    PYTHONPATH=. python -m pytest -q

## محدودیت‌ها

- سرویس منبع شخص ثالث و غیررسمی است؛ پاسخ، پایداری، دقت و پوشش منطقه‌ای آن تضمین نمی‌شود.
- Backend فقط فیلدهای مجاز و موجود را عبور می‌دهد و برای دادهٔ ناموجود مقدار ساختگی تولید نمی‌کند.
- API فعلی تاریخچهٔ مسابقات یا آمار کیل، دث و برد را تضمین نمی‌کند.
- این سرویس هنوز به PostgreSQL یا Firebase متصل نیست؛ cache آن درون‌حافظه‌ای و موقت است.
- Rank Tracker و فهرست لینک کلیپ‌ها در نسخهٔ فعلی اپ به‌صورت محلی روی دستگاه ذخیره می‌شوند، نه در Backend.
