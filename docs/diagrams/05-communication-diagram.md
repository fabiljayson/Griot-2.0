# Communication Diagram — Griot 2.0

## 1. Story Reading Communication

```mermaid
flowchart LR
    subgraph "Flutter Client"
        U["User"]
        SS["StoriesScreen"]
        SD["StoryDetailScreen"]
        SP["StoryProvider"]
        SR["StoryRepository"]
        AC["ApiClient"]
        AI["AuthInterceptor"]
        DB["AppDatabase"]
    end

    subgraph "Backend API"
        SV["StoryViewSet"]
        SVS["StorySerializer"]
        Mod["Story Model"]
    end

    U -- "1. select story" --> SS
    SS -- "2. navigate(slug)" --> SD
    SD -- "3. fetchStory(slug)" --> SP
    SP -- "4. getStory(slug)" --> SR
    SR -- "5. GET /api/stories/{slug}/" --> AC
    AC -- "6. inject Bearer token" --> AI
    AI -- "7. forwarded request" --> SV
    SV -- "8. get_object()" --> Mod
    Mod -- "9. story data" --> SV
    SV -- "10. serialize" --> SVS
    SVS -- "11. JSON response" --> AI
    AI -- "12. pass response" --> AC
    AC -- "13. StoryModel" --> SR
    SR -- "14. update state" --> SP
    SP -- "15. story data" --> SD
    SD -- "16. render content" --> U

    SD -- "17. cache story" --> DB
    U -- "18. scroll 50%" --> SD
    SD -- "19. updateProgress(50%)" --> SP
    SP -- "20. POST /stories/{slug}/progress/" --> AC
    AC --> SV
```

## 2. Authentication Communication

```mermaid
flowchart LR
    subgraph "Flutter Client"
        U["User"]
        LS["LoginScreen"]
        AR["AuthRepository"]
        AC["ApiClient"]
        AW["AuthWrapper"]
        HS["HomeScreen"]
    end

    subgraph "Backend API"
        TV["TokenObtainPairView"]
        RV["RegisterView"]
        MV["MeView"]
    end

    U -- "1. enter credentials" --> LS
    LS -- "2. login(user, pass)" --> AR
    AR -- "3. POST /api/auth/token/" --> AC
    AC -- "4. credentials" --> TV
    TV -- "5. JWT {access, refresh}" --> AR
    AR -- "6. store tokens" --> AR
    AR -- "7. AuthState.authenticated" --> AW
    AW -- "8. rebuild" --> HS
    HS -- "9. show home" --> U
```

## 3. Offline Queue Communication

```mermaid
flowchart LR
    subgraph "Flutter Client"
        U["User"]
        App["App Widget"]
        OQI["OfflineQueueInterceptor"]
        CS["ConnectivityService"]
        ORepo["OfflineRequestRepo"]
        OSM["OfflineSyncManager"]
        AC["ApiClient"]
    end

    subgraph "Backend API"
        API["Django REST Views"]
    end

    U -- "1. bookmark story" --> App
    App -- "2. POST bookmark/" --> OQI
    OQI -- "3. isOnline?" --> CS
    CS -- "4. false" --> OQI
    OQI -- "5. saveRequest()" --> ORepo
    OQI -- "6. 202 Queued" --> App
    App -- "7. show queued msg" --> U

    CS -- "8. connectivity restored" --> OSM
    OSM -- "9. getPending()" --> ORepo
    ORepo -- "10. pending list" --> OSM
    OSM -- "11. replay POST bookmark/" --> AC
    AC -- "12. HTTP request" --> API
    API -- "13. 201 Created" --> OSM
    OSM -- "14. markCompleted()" --> ORepo
```

## 4. QR Scan Communication

```mermaid
flowchart LR
    subgraph "Flutter Client"
        U["User"]
        QR["QRScannerWidget"]
        AD["ArtifactDetailScreen"]
        QAS["QrApiService"]
        AC["ApiClient"]
    end

    subgraph "Backend API"
        AV["ArtifactViewSet"]
        AM["Artifact Model"]
        QS["QRCodeScan Model"]
    end

    U -- "1. scan QR code" --> QR
    QR -- "2. decode slug" --> QR
    QR -- "3. lookupArtifact(slug)" --> QAS
    QAS -- "4. GET /api/artifacts/lookup/" --> AC
    AC -- "5. request" --> AV
    AV -- "6. find artifact" --> AM
    AV -- "7. record scan" --> QS
    AV -- "8. artifact JSON" --> QAS
    QAS -- "9. navigate" --> AD
    AD -- "10. display info" --> U
```

## 5. Media Generation Communication

```mermaid
flowchart LR
    subgraph "Flutter Client"
        U["User"]
        VGS["VideoGenerationSheet"]
        VPS["VideoStatusPoller"]
        VAS["VideoApiService"]
        AC["ApiClient"]
    end

    subgraph "Backend API"
        VV["VideoViewSet"]
        VJ["VideoGenerationJob"]
    end

    subgraph "External"
        Luma["Luma AI API"]
    end

    U -- "1. enter prompt" --> VGS
    VGS -- "2. generateVideo()" --> VAS
    VAS -- "3. POST /api/media/videos/" --> AC
    AC --> VV
    VV -- "4. create job" --> VJ
    VV -- "5. call Luma AI" --> Luma
    Luma -- "6. job_id" --> VV
    VV -- "7. job created" --> VAS
    VAS -- "8. start polling" --> VPS

    loop "Poll every 10s"
        VPS -- "9. GET /status/video/{id}/" --> AC
        AC --> VV
        VV -- "10. job status" --> VPS
        VPS -- "11. update badge" --> VGS
    end

    VV -- "12. completed + video_url" --> VPS
    VPS -- "13. video ready" --> VGS
    VGS -- "14. show player" --> U
```
