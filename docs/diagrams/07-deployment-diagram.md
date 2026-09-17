# Deployment Diagram — Griot 2.0

## System Deployment Architecture

```mermaid
flowchart TB
    subgraph "Client Devices"
        subgraph "Mobile"
            iOS["📱 iOS Device<br/>(Flutter App)"]
            Android["📱 Android Device<br/>(Flutter App)"]
        end
        subgraph "Web"
            PWA["🌐 Web Browser<br/>(Flutter PWA)"]
        end
    end

    subgraph "Flutter Client Layer"
        direction LR
        UI["Flutter UI<br/>(MaterialApp)"]
        Riverpod["Riverpod<br/>State Management"]
        Dio["Dio HTTP Client<br/>(+ interceptors)"]
        SQLite["SQLite / IndexedDB<br/>(Local Cache)"]
    end

    subgraph "Network Layer"
        HTTPS["HTTPS"]
        Ngrok["Ngrok Tunnel<br/>(dev testing)"]
    end

    subgraph "Backend Server"
        direction TB

        subgraph "Django Application"
            WSGI["WSGI / ASGI<br/>Server"]
            DRF["Django REST<br/>Framework"]
            JWT["SimpleJWT<br/>Authentication"]
        end

        subgraph "Django Apps"
            UsersApp["users<br/>(Auth & Roles)"]
            StoriesApp["stories<br/>(Content)"]
            QRCodesApp["qr_codes<br/>(Artifacts)"]
            GamificationApp["gamification<br/>(Quizzes & Badges)"]
            MediaApp["media_app<br/>(Video & TTS)"]
            APIApp["api<br/>(Health & Analytics)"]
        end

        subgraph "Database"
            SQLiteProd["SQLite<br/>(Development)"]
            PostgreSQL["PostgreSQL<br/>(Production)"]
        end

        subgraph "File Storage"
            MediaFiles["Media Files<br/>(Stories, Artifacts)"]
        end
    end

    subgraph "External Services"
        direction LR
        LumaAI["🎬 Luma AI<br/>Dream Machine<br/>(Video Generation)"]
        TTSService["🔊 TTS Provider<br/>(Audio Narration)"]
        Sentry["🐛 Sentry<br/>(Error Monitoring)"]
    end

    subgraph "DevOps & Monitoring"
        direction LR
        NgrokTunnel["Ngrok<br/>(Tunneling)"]
        HealthCheck["Health Endpoints<br/>/api/health/*"]
        StructLog["Structured<br/>JSON Logging"]
    end

    %% Client connections
    iOS --> HTTPS
    Android --> HTTPS
    PWA --> HTTPS
    iOS -.-> Ngrok
    Android -.-> Ngrok

    %% Flutter internals
    UI --> Riverpod
    Riverpod --> Dio
    Dio --> SQLite

    %% Network to backend
    HTTPS --> WSGI
    Ngrok --> WSGI

    %% Django internals
    WSGI --> DRF
    DRF --> JWT
    DRF --> UsersApp
    DRF --> StoriesApp
    DRF --> QRCodesApp
    DRF --> GamificationApp
    DRF --> MediaApp
    DRF --> APIApp

    %% Database
    UsersApp --> SQLiteProd
    StoriesApp --> SQLiteProd
    QRCodesApp --> SQLiteProd
    GamificationApp --> SQLiteProd
    MediaApp --> SQLiteProd
    SQLiteProd -.-> PostgreSQL

    %% File storage
    StoriesApp --> MediaFiles
    QRCodesApp --> MediaFiles

    %% External services
    MediaApp --> LumaAI
    MediaApp --> TTSService
    APIApp --> Sentry
```

## Development vs Production

```mermaid
flowchart LR
    subgraph "Development Environment"
        DevApp["Flutter App<br/>(flutter run)"]
        DevServer["Django Dev Server<br/>(manage.py runserver)"]
        DevDB["SQLite<br/>(african_teller.db)"]
        DevNgrok["Ngrok<br/>(ngrok-free.app)"]
        DevMedia["Media: /media/"]

        DevApp --> DevNgrok
        DevNgrok --> DevServer
        DevServer --> DevDB
        DevServer --> DevMedia
    end

    subgraph "Production Environment"
        ProdApp["Flutter Web/Mobile<br/>(built assets)"]
        ProdServer["Django + Gunicorn<br/>(WSGI)"]
        ProdDB["PostgreSQL<br/>(managed)"]
        ProdCDN["CDN / Static Files"]
        ProdMedia["Cloud Storage<br/>(S3 / GCS)"]
        ProdSentry["Sentry<br/>(error tracking)"]

        ProdApp -->|HTTPS| ProdCDN
        ProdCDN -->|API calls| ProdServer
        ProdServer --> ProdDB
        ProdServer --> ProdMedia
        ProdServer --> ProdSentry
    end
```

## Deployment Details

| Component | Development | Production |
|---|---|---|
| **Frontend** | `flutter run` (hot reload) | Built APK/IPA/Web assets |
| **Backend** | `manage.py runserver` | Gunicorn + Nginx |
| **Database** | SQLite (`african_teller.db`) | PostgreSQL |
| **File Storage** | Local `media/` directory | Cloud storage (S3/GCS) |
| **Tunneling** | Ngrok (`ngrok-free.app`) | N/A (direct HTTPS) |
| **Monitoring** | Console logs | Sentry + structured JSON logs |
| **SSL/TLS** | Ngrok-provided | Let's Encrypt / Cloudflare |
| **CORS** | `CORS_ALLOW_ALL_ORIGINS = True` | Restricted origins |
| **Media Serving** | Django `static()` | Nginx / CDN |

## Environment Variables

| Variable | Development | Production |
|---|---|---|
| `DEBUG` | `True` | `False` |
| `SECRET_KEY` | `django-insecure-dev-only...` | Secure random key |
| `ALLOWED_HOSTS` | `localhost, 127.0.0.1, *.ngrok-free.app` | `africanteller.org` |
| `DATABASE_URL` | — (SQLite) | `postgres://...` |
| `SENTRY_DSN` | Optional | Required |
| `API_BASE_URL` | `http://10.0.2.2:8000` | `https://api.africanteller.org` |
| `NGROK_URL` | `https://xxxx.ngrok-free.app` | — |
