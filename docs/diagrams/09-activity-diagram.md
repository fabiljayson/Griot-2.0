# Activity Diagrams — Griot 2.0

## 1. User Registration & Onboarding

```mermaid
flowchart TD
    Start([User opens app]) --> AuthCheck{AuthWrapper<br/>checks tokens}

    AuthCheck -->|No tokens| LoginScreen[Show LoginScreen]
    AuthCheck -->|Valid tokens| HomeScreen[Show HomeScreen]

    LoginScreen --> HasAccount{Has account?}

    HasAccount -->|Yes| EnterCreds[Enter credentials]
    HasAccount -->|No| TapRegister[Tap "Create account"]

    TapRegister --> FillForm[Fill registration form<br/>username, email, password]
    FillForm --> ValidateForm{Form valid?}

    ValidateForm -->|No| ShowErrors[Show validation errors]
    ShowErrors --> FillForm

    ValidateForm -->|Yes| OnlineNow{Online?}
    OnlineNow -->|Yes| SubmitReg[POST /api/auth/register/<br/>via ServerAuthRepository]
    OnlineNow -->|No| QueueReg[Queue registration<br/>offline_requests<br/>AuthStatus → pendingSync]
    QueueReg --> ShowQueued[Show "Account saved —<br/>will sync when online"]
    ShowQueued --> HomeScreen

    SubmitReg --> RegSuccess{Registration<br/>successful?}

    RegSuccess -->|No| ShowRegError[Show error message]
    ShowRegError --> FillForm

    RegSuccess -->|Yes| AutoLogin[Auto-login with credentials]
    AutoLogin --> StoreTokens[Store JWT tokens<br/>access + refresh (local)]

    EnterCreds --> AuthOnline{Online?}
    AuthOnline -->|Yes| ValidateCreds[POST /api/auth/token/]
    AuthOnline -->|No| AuthFallback[LocalAuthRepository etc.<br/>serve cached session<br/>(AuthStatus → pendingSync)]
    AuthFallback --> StoreTokens

    ValidateCreds --> CredsValid{Credentials<br/>valid?}

    CredsValid -->|No| ShowLoginError[Show error message]
    ShowLoginError --> EnterCreds

    CredsValid -->|Yes| StoreTokens

    StoreTokens --> HomeScreen

    HomeScreen --> Welcome{First time?}
    Welcome -->|Yes| ShowTour[Show onboarding tour]
    Welcome -->|No| ShowContent[Show personalized content]
    ShowTour --> ShowContent
    ShowContent --> End([App ready])
```

## 2. Story Creation & Moderation

```mermaid
flowchart TD
    Start([Contributor taps "Create Story"]) --> AuthCheck{Is Contributor+?}

    AuthCheck -->|No| ShowDenied[Show access denied]
    ShowDenied --> End1([Stop])

    AuthCheck -->|Yes| OpenForm[Open StoryFormScreen]
    OpenForm --> FillStory[Fill story details<br/>title, content, category,<br/>language, region]
    FillStory --> AddMedia[Add cover image<br/>(optional)]
    AddMedia --> Preview[Preview story]
    Preview --> SubmitStory{Submit for<br/>review?}

    SubmitStory -->|Save Draft| SaveDraft[Save as Draft]
    SaveDraft --> DraftSaved[Story saved locally]
    DraftSaved --> End2([Draft saved])

    SubmitStory -->|Submit| SubmitToAPI[POST /api/stories/]
    SubmitToAPI --> APICreate{API creates<br/>story?}

    APICreate -->|No| ShowCreateError[Show error]
    ShowCreateError --> FillStory

    APICreate -->|Yes| SetPending[Status → Pending]
    SetPending --> NotifyAuthor[Notify author:<br/>"Submitted for review"]
    NotifyAuthor --> WaitReview[Wait for<br/>moderation]

    WaitReview --> ModCheck{Admin/Manager<br/>reviews}

    ModCheck -->|Approve| Publish[Status → Published]
    Publish --> NotifyApproved[Notify: "Story published!"]
    NotifyApproved --> LiveOnPlatform[Story visible to all]
    LiveOnPlatform --> End3([Story live])

    ModCheck -->|Reject| RejectStory[Status → Rejected]
    RejectStory --> NotifyRejected[Notify: "Needs revision"]
    NotifyRejected --> Revise[Author revises story]
    Revise --> FillStory

    ModCheck -->|Archive| ArchiveStory[Status → Archived]
    ArchiveStory --> End4([Story archived])
```

## 3. Quiz Taking & Gamification

```mermaid
flowchart TD
    Start([User selects quiz]) --> AuthCheck{Authenticated?}

    AuthCheck -->|No| PromptLogin[Prompt to login]
    PromptLogin --> End1([Stop])

    AuthCheck -->|Yes| CheckExisting{Existing in-<br/>progress attempt?}

    CheckExisting -->|Yes| ResumeAttempt[Resume attempt]
    CheckExisting -->|No| StartQuiz[Start quiz — local SQLite<br/>via GamificationApiService →<br/>LocalGamificationRepository]

    ResumeAttempt --> LoadQuestions[Load questions (local)]
    StartQuiz --> CreateAttempt[Create QuizAttempt (local)]
    CreateAttempt --> LoadQuestions

    LoadQuestions --> ShowQuestion[Display question<br/>with 4 options]

    ShowQuestion --> SelectAnswer[User selects answer]
    SelectAnswer --> GradeAnswer{Correct?}

    GradeAnswer -->|Yes| ShowCorrect[Show ✓ + explanation]
    GradeAnswer -->|No| ShowIncorrect[Show ✗ + correct answer]

    ShowCorrect --> UpdateProgress[Update progress bar]
    ShowIncorrect --> UpdateProgress

    UpdateProgress --> MoreQuestions{More<br/>questions?}

    MoreQuestions -->|Yes| ShowQuestion
    MoreQuestions -->|No| FinishQuiz[Finish quiz — persist result<br/>locally; SQLite mirror]

    FinishQuiz --> CalculateScore[Calculate score]
    CalculateScore --> Passed{Score >=<br/>passing_score?}

    Passed -->|Yes| AwardXP[Award XP — update<br/>local user profile]
    Passed -->|No| NoXP[No XP awarded]

    AwardXP --> CheckLevel{Level up?}
    CheckLevel -->|Yes| LevelUp[Increment level<br/>Show celebration]
    CheckLevel -->|No| CheckBadges

    NoXP --> CheckBadges[Check badge eligibility<br/>(leaderboard is local)]

    CheckBadges --> BadgesEarned{New badges?}
    BadgesEarned -->|Yes| AwardBadges[ Award badges<br/>+ XP]
    BadgesEarned -->|No| CheckCerts

    AwardBadges --> CheckCerts{Certificate<br/>eligible?}
    CheckCerts -->|Yes| IssueCert[Issue certificate<br/>Generate PDF]
    CheckCerts -->|No| ShowResults

    IssueCert --> ShowResults[Show results screen<br/>score, XP, badges, cert]
    LevelUp --> ShowResults

    ShowResults --> End2([Quiz complete])
```

## 4. Offline Sync Process

```mermaid
flowchart TD
    Start([App detects connectivity change]) --> IsOnline{Device<br/>online?}

    IsOnline -->|No| QueueMode[Enter offline mode]
    QueueMode --> ShowOffline[Show "Offline" indicator]

    ShowOffline --> UserAction{User action}

    UserAction -->|API request| CheckMethod{HTTP method?}
    CheckMethod -->|GET| TryCache[Try local cache]
    TryCache --> CacheHit{Cache hit?}
    CacheHit -->|Yes| ReturnCache[Return cached data]
    CacheHit -->|No| ShowErrorMsg[Show "No data available"]

    CheckMethod -->|POST/PUT/PATCH/DELETE| QueueRequest[Queue request<br/>in offline_requests]
    QueueRequest --> ShowQueued[Show "Queued for sync"]
    ShowQueued --> UserAction

    IsOnline -->|Yes| CheckPending{Pending<br/>queued requests?}

    CheckPending -->|No| NormalMode[Normal online mode]
    NormalMode --> UserAction2[Handle user actions normally]

    CheckPending -->|Yes| StartSync[Start sync process]
    StartSync --> FetchPending[Fetch all pending requests]
    FetchPending --> HasReqs{Requests<br/>found?}

    HasReqs -->|No| SyncDone[Sync complete]
    HasReqs -->|Yes| ProcessReqs[Process requests<br/>in order]

    ProcessReqs --> ExecReq[Execute request<br/>via ApiClient]
    ExecReq --> ReqSuccess{Server<br/>response 2xx?}

    ReqSuccess -->|Yes| MarkComplete[Mark request completed]
    ReqSuccess -->|No| CheckRetries{Retry count<br/>< max?}

    CheckRetries -->|Yes| IncrementRetry[Increment retry count<br/>Apply backoff delay]
    IncrementRetry --> ProcessReqs

    CheckRetries -->|No| MarkFailed[Mark request failed]

    MarkComplete --> MoreReqs{More<br/>requests?}
    MarkFailed --> MoreReqs

    MoreReqs -->|Yes| ProcessReqs
    MoreReqs -->|No| SyncDone

    SyncDone --> SyncUsers{Pending user<br/>registrations?}
    SyncUsers -->|Yes| RegisterUsers[Sync offline registrations]
    SyncUsers -->|No| NotifySync[Notify: "All synced"]
    RegisterUsers --> NotifySync
    NotifySync --> End([Sync complete])
```

## 5. QR Code Scan → Artifact Discovery

```mermaid
flowchart TD
    Start([User opens QR Scanner]) --> InitCamera[Initialize camera]
    InitCamera --> ShowOverlay[Show scanner overlay<br/>with African border motif]
    ShowOverlay --> Waiting[Waiting for scan...]

    Waiting --> ScanDetected[QR code detected]
    ScanDetected --> DecodeQR[Decode QR → slug/ID]
    DecodeQR --> ShowLoading[Show loading indicator]

    ShowLoading --> LookupArtifact[GET /api/artifacts/lookup/]
    LookupArtifact --> Found{Artifact<br/>found?}

    Found -->|No| ShowNotFound[Show "Artifact not found"]
    ShowNotFound --> Waiting

    Found -->|Yes| RecordScan[Record QR scan<br/>device, IP, GPS]
    RecordScan --> LoadArtifact[Load artifact details]

    LoadArtifact --> ShowArtifact[Show ArtifactDetailScreen<br/>title, image, description,<br/>culture, region, materials]

    ShowArtifact --> ShowRelated[Load related stories]
    ShowRelated --> HasStories{Related<br/>stories?}

    HasStories -->|Yes| ShowStories[Display related<br/>story cards]
    HasStories -->|No| ShowNoStories[Show "No related stories"]

    ShowStories --> UserChoice{User action}

    UserChoice -->|Tap story| NavigateStory[Navigate to<br/>StoryDetailScreen]
    UserChoice -->|Play audio| PlayTTS[Play TTS narration<br/>for artifact]
    UserChoice -->|Share| ShareArtifact[Share artifact<br/>to social platform]
    UserChoice -->|Back| Waiting

    NavigateStory --> End1([Story opened])
    PlayTTS --> UserChoice
    ShareArtifact --> UserChoice
    ShowNoStories --> UserChoice
```

## 6. AI Video Generation Process

```mermaid
flowchart TD
    Start([Contributor taps "Generate Video"]) --> AuthCheck{Contributor+?}

    AuthCheck -->|No| ShowDenied[Show access denied]
    ShowDenied --> End1([Stop])

    AuthCheck -->|Yes| OpenSheet[Open VideoGenerationSheet]
    OpenSheet --> EnterPrompt[Enter video prompt<br/>custom description]
    EnterPrompt --> SelectStory[Select story for video]
    SelectStory --> Preview[Preview prompt + story]
    Preview --> SubmitJob[POST /api/media/videos/]

    SubmitJob --> JobCreated{Job created?}
    JobCreated -->|No| ShowError[Show error]
    ShowError --> EnterPrompt

    JobCreated -->|Yes| StartPolling[Start status polling<br/>every 10 seconds]
    StartPolling --> ShowProgress[Show progress indicator]

    ShowProgress --> PollStatus[GET /api/media/status/video/{id}/]
    PollStatus --> JobStatus{Job status?}

    JobStatus -->|Pending| Wait[Wait 10 seconds]
    Wait --> PollStatus

    JobStatus -->|Processing| UpdateProgress[Update progress %]
    UpdateProgress --> ShowProgress

    JobStatus -->|Failed| ShowFailed[Show error message]
    ShowFailed --> RetryOption{Retry?}
    RetryOption -->|Yes| SubmitJob
    RetryOption -->|No| End2([Cancelled])

    JobStatus -->|Completed| VideoReady[Video ready!]
    VideoReady --> ShowPlayer[Show VideoPlayerWidget]
    ShowPlayer --> PlayVideo[Play generated video]
    PlayVideo --> Actions{User actions}

    Actions -->|Download| Download[Download video]
    Actions -->|Share| Share[Share video link]
    Actions -->|Regenerate| EnterPrompt

    Download --> End3([Video saved])
    Share --> End4([Video shared])
```
