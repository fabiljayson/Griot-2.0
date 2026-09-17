# Ngrok Setup for African Teller

This guide explains how to expose your local Django backend to a physical mobile device running the Flutter app using ngrok.

## Prerequisites

1. **ngrok installed and authenticated**
   ```bash
   ngrok version
   ngrok config add-authtoken YOUR_TOKEN
   ```

2. **Python and Django installed**
   ```bash
   cd backend
   pip install -r requirements.txt
   ```

3. **Flutter app with dependencies**
   ```bash
   cd frontend
   flutter pub get
   ```

## Quick Start

### Option 1: Use the setup script (recommended)
```bash
chmod +x setup_ngrok.sh
./setup_ngrok.sh
```

### Option 2: Manual setup

#### Step 1: Start Django server
```bash
cd backend
python manage.py runserver 0.0.0.0:8000
```

#### Step 2: Start ngrok tunnel (in a separate terminal)
```bash
ngrok http 8000
```

#### Step 3: Copy ngrok URL
1. Open http://localhost:4040 in your browser
2. Copy the HTTPS URL (e.g., `https://xxxx-xx-xx-xx-xx.ngrok-free.app`)

#### Step 4: Run Flutter app with ngrok URL
```bash
cd frontend
flutter run --dart-define=NGROK_URL=https://xxxx-xx-xx-xx-xx.ngrok-free.app
```

Or for release mode:
```bash
flutter run --release --dart-define=NGROK_URL=https://xxxx-xx-xx-xx-xx.ngrok-free.app
```

## Configuration Changes Made

### 1. Django Settings (`backend/config/settings/dev.py`)

Updated to allow ngrok traffic:

```python
ALLOWED_HOSTS = [
    'localhost',
    '127.0.0.1',
    '.ngrok-free.app',
    '.ngrok.io',
    '*',
]

CORS_ALLOW_ALL_ORIGINS = True

CORS_ALLOW_HEADERS = [
    'accept',
    'accept-encoding',
    'authorization',
    'content-type',
    'dnt',
    'origin',
    'user-agent',
    'x-csrftoken',
    'x-requested-with',
    'ngrok-skip-browser-warning',
]
```

### 2. Flutter ApiClient (`frontend/lib/core/network/api_client.dart`)

Updated to support ngrok URL and bypass the warning page:

- Added `ngrok-skip-browser-warning: true` header
- Added `Content-Type: application/json` header
- Added `withNgrok()` factory method
- Uses `AppConstants.effectiveBaseUrl` which automatically switches to ngrok URL when configured

### 3. AppConstants (`frontend/lib/core/constants/app_constants.dart`)

Added ngrok configuration:

```dart
static const String ngrokUrl = String.fromEnvironment('NGROK_URL');
static bool get useNgrok => ngrokUrl.isNotEmpty;
static String get effectiveBaseUrl {
  if (useNgrok) {
    return '$ngrokUrl/api/';
  }
  return apiBaseUrl;
}
```

## Verification

### 1. Test Django API directly
Open in your phone's browser:
```
https://xxxx-xx-xx-xx-xx.ngrok-free.app/api/stories/
```
You should see JSON data, not the ngrok warning page.

### 2. Test Flutter app
1. Launch the Flutter app on your physical device
2. Try to fetch stories or authenticate
3. Check Django logs for incoming requests

### 3. Check ngrok dashboard
Open http://localhost:4040 to see:
- Request logs
- Response times
- Error details

## Troubleshooting

### "403 Forbidden" error
- Ensure `ngrok-skip-browser-warning: true` header is included
- Check that `ALLOWED_HOSTS` includes `.ngrok-free.app`

### "CORS error" in Flutter
- Verify `CORS_ALLOW_HEADERS` includes all required headers
- Check that `CORS_ALLOW_ALL_ORIGINS = True` is set

### ngrok warning page appears
- Make sure the `ngrok-skip-browser-warning` header is being sent
- Try accessing the URL in a browser first to get the ngrok cookies

### Flutter app can't connect
- Verify the ngrok URL is correct (check http://localhost:4040)
- Ensure both Django server and ngrok are running
- Check network permissions on your mobile device

## Security Notes

- **ngrok free tier limitations**: URLs change on restart, limited connections
- **Never use in production**: This setup is for development/testing only
- **Keep ngrok running**: The tunnel stops when you close the terminal

## Cleanup

To stop all services:
1. Press `Ctrl+C` in the terminal running the setup script
2. Or manually kill the processes:
   ```bash
   pkill -f "python manage.py runserver"
   pkill -f "ngrok http"
   ```