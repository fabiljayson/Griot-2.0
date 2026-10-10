using System;
using System.Collections;
using Griot.VR.Authentication;
using Griot.VR.MobileVR;
using Griot.VR.Network;
using Griot.VR.UI;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.XR;

namespace Griot.VR
{
    /// <summary>
    /// Entry point of the VR application: validates the launch link,
    /// exchanges it for a session through <see cref="GriotApiClient"/>,
    /// confirms the platform runtime is alive, then hands off to the first
    /// playable scene — chosen from the backend payload when one arrived.
    /// </summary>
    /// <remarks>
    /// <para>
    /// The scene flow is deliberately one-way (Bootstrap → first
    /// environment) and every failure ends somewhere the reader can see it.
    /// This class orchestrates; it is the only scene-level script allowed
    /// to start API coroutines, and it does so exclusively through
    /// <see cref="GriotApiClient"/> (see the project README).
    /// </para>
    /// <para>
    /// Failure never blocks the museum: a refused token or an unreachable
    /// server leaves the scene-local content in place and queues an error
    /// panel for when the environment is ready, so a headset with no network
    /// still opens into a usable gallery.
    /// </para>
    /// <para>
    /// Platform differences live behind <see cref="IGriotVRRuntime"/> —
    /// OpenXR headset (<see cref="HeadsetVRRuntime"/>) or phone in a
    /// SHINECON viewer (<see cref="MobileVRRuntime"/>). Everything above
    /// that seam (deep link, exchange, payload, scenes, progress, errors)
    /// is shared and unchanged; see §2 of the Mobile VR spec.
    /// </para>
    /// </remarks>
    [DefaultExecutionOrder(-100)]
    public sealed class GriotVrBootstrap : MonoBehaviour
    {
        public const string MuseumSceneName = "Museum";
        public const string LoadingSceneName = "Loading";

        /// <summary>Quest 2/3 default refresh rate. Milestone 12 tunes this.</summary>
        public const int PreferredRefreshRate = 72;

        const string LogPrefix = "[GriotVR] ";

        [SerializeField] bool loadMuseumOnStart = true;

        // The museum test scene stays reachable via this field for local
        // iteration, but the app boots into the first real environment.
        [SerializeField] string nextScene = EnvironmentLoader.CameroonMuseumSceneName;

        [Tooltip("Optional API config asset. Without one: the deployed API on device, the mock stub in the Editor.")]
        [SerializeField] GriotApiConfig apiConfig;

        [Tooltip("Auto picks headset when an XR session is live, phone VR on mobile platforms, headset otherwise. Force either mode to test one path deterministically.")]
        [SerializeField] GriotVRRuntimeMode runtimeMode = GriotVRRuntimeMode.Auto;

        [Tooltip("Optional frame-pacing override for the phone runtime; built-in defaults (60 fps) apply when empty.")]
        [SerializeField] MobileVRPerformanceSettings mobilePerformanceSettings;

        static GriotVrBootstrap instance;

        /// <summary>
        /// The runtime the current session booted (never null after
        /// <see cref="BootRoutine"/> starts). <see cref="EnvironmentLoader"/>
        /// reads <see cref="IGriotVRRuntime.PlacementRoot"/> from it so both
        /// rigs are placed by the same code path.
        /// </summary>
        public static IGriotVRRuntime ActiveRuntime { get; private set; }

        AuthManager auth;
        GriotApiClient apiClient;
        bool exchangeInFlight;
        bool lastExchangeSucceeded;
        bool hasPendingError;
        string pendingErrorTitle;
        string pendingErrorMessage;

        void Awake()
        {
            if (instance != null && instance != this)
            {
                Destroy(gameObject);
                return;
            }

            instance = this;
            DontDestroyOnLoad(gameObject);

            // Screen, not Application: Unity 6 only exposes the sleep
            // policy on Screen, and neither a headset build nor a phone in
            // a viewer must ever doze off mid-visit. Frame pacing is per
            // runtime (72 Hz headset, mobile performance settings) and is
            // applied in IGriotVRRuntime.Initialize.
            Screen.sleepTimeout = SleepTimeout.NeverSleep;
            Application.deepLinkActivated += OnDeepLinkActivated;
        }

        void Start()
        {
            StartCoroutine(BootRoutine());
        }

        void OnDestroy()
        {
            if (instance != this) return;
            instance = null;
            Application.deepLinkActivated -= OnDeepLinkActivated;
            ExperienceContent.ArtifactViewed -= OnArtifactViewed;
            EnvironmentLoader.EnvironmentReady -= OnEnvironmentReady;
            ActiveRuntime?.Shutdown();
            ActiveRuntime = null;
        }

        IEnumerator BootRoutine()
        {
            HandleInitialDeepLink();

            var mode = ResolveRuntimeMode();
            ActiveRuntime = mode == GriotVRRuntimeMode.MobileVR
                ? (IGriotVRRuntime)new MobileVRRuntime(mobilePerformanceSettings)
                : new HeadsetVRRuntime();
            Debug.Log(LogPrefix + "Runtime mode: " + mode + ".");

            yield return ActiveRuntime.Initialize();

            if (!string.IsNullOrEmpty(ActiveRuntime.BootProblem))
            {
                // Only the phone path ever fills this in (no gyroscope);
                // the headset path's missing-rig case stays the log error
                // it always was.
                ShowErrorWhenReady("Mobile VR unavailable", ActiveRuntime.BootProblem);
            }

            yield return ConnectToBackend();

            if (loadMuseumOnStart && !string.IsNullOrEmpty(nextScene))
            {
                LoadExperienceScene();
            }
        }

        /// <summary>
        /// Which runtime runs this session (§2 of the Mobile VR spec).
        /// Deterministic precedence: an explicit inspector choice wins
        /// (that is how the Editor simulates the phone), then the
        /// <c>USE_MOCK_API</c> validation build forces the phone path, then
        /// a live XR session means headset, then any mobile platform means
        /// phone — and the desktop Editor without a device stays on the
        /// historic headset path so existing Quest testing is untouched.
        /// </summary>
        GriotVRRuntimeMode ResolveRuntimeMode()
        {
            if (runtimeMode != GriotVRRuntimeMode.Auto) return runtimeMode;
            if (MobileVRTestMode.Enabled) return GriotVRRuntimeMode.MobileVR;
            if (XRSettings.isDeviceActive) return GriotVRRuntimeMode.HeadsetVR;
            if (Application.isMobilePlatform) return GriotVRRuntimeMode.MobileVR;
            return GriotVRRuntimeMode.HeadsetVR;
        }

        // ---- backend connection ---------------------------------------------

        /// <summary>
        /// Exchange the launch token and apply the experience payload — the
        /// only place a scene script starts an API coroutine, always through
        /// <see cref="GriotApiClient"/>. Ends either with
        /// <see cref="ExperienceContent"/> populated, or with an error panel
        /// queued for when the environment loads; scene-local content is
        /// the fallback either way.
        /// </summary>
        IEnumerator ConnectToBackend()
        {
            // USE_MOCK_API validation builds (phone APK) always stub — §26
            // of the Mobile VR spec: on-device mobile testing must never
            // reach the deployed API.
            var config = apiConfig != null
                ? apiConfig
                : MobileVRTestMode.Enabled
                    ? GriotApiConfig.CreateMockDefault()
                    : GriotApiConfig.CreateRuntimeDefault();
            var tokens = new VRTokenStore();
            apiClient = new GriotApiClient(config, tokens);
            auth = new AuthManager(apiClient, tokens);

            ExperienceContent.ArtifactViewed -= OnArtifactViewed;
            ExperienceContent.ArtifactViewed += OnArtifactViewed;

            Debug.Log(LogPrefix + (config.UseMockApi
                ? "API config: mock stub (development only)."
                : "API config: " + config.BaseUrl + "."));

            var launch = DeepLinkManager.LastLaunch;
            if (launch != null)
            {
                yield return ExchangeAndApply(launch);
                yield break;
            }

            if (!config.UseMockApi)
            {
                // The normal state of a headset that was put on without the
                // phone app: local content, and a log line for whoever
                // next plugs it into a console.
                Debug.Log(
                    LogPrefix + "No launch link received; scene content stays local. " +
                    "Open this experience from the Griot app for live data.");
                yield break;
            }

            ApiResult<ExperiencePayload> payload = null;
            yield return apiClient.GetExperience("cameroon-heritage-museum", r => payload = r);
            if (payload.Ok && payload.Data != null)
            {
                ApplyExperience(payload.Data);
            }
            else
            {
                FailConnect(payload.ErrorCode, null);
            }
        }

        /// <summary>
        /// Run one launch exchange. On success the payload is applied;
        /// on failure the error is logged, mapped to headset copy and
        /// queued for the error panel. Never throws, never retries —
        /// a launch token is single-use, so a retry would just burn the
        /// <c>token_used</c> response.
        /// </summary>
        IEnumerator ExchangeAndApply(LaunchData launch)
        {
            if (exchangeInFlight)
            {
                Debug.LogWarning(
                    LogPrefix + "A launch exchange is already running; " +
                    "keeping the launch currently being opened.");
                yield break;
            }

            exchangeInFlight = true;
            AuthManager.Result result = null;
            yield return auth.Exchange(launch, r => result = r);
            exchangeInFlight = false;

            lastExchangeSucceeded = result.Ok;
            if (result.Ok)
            {
                ApplyExperience(result.Exchange.Experience);
            }
            else
            {
                FailConnect(result.ErrorCode, result.UserMessage);
            }
        }

        void ApplyExperience(ExperiencePayload payload)
        {
            if (payload == null)
            {
                FailConnect(GriotApiClient.ErrorCodeInvalidResponse, null);
                return;
            }

            ExperienceContent.Set(payload);
            Debug.Log(
                LogPrefix + "Experience loaded: '" + payload.Title + "' (" +
                payload.ArtifactCount + " artifacts, scene '" +
                payload.SceneIdentifier + "').");
        }

        void FailConnect(string errorCode, string userMessage)
        {
            var copy = userMessage ?? AuthManager.UserMessageFor(errorCode);
            Debug.LogError(
                LogPrefix + "Backend connection failed (" +
                (errorCode ?? "unknown") + "): " + copy);
            ShowErrorWhenReady("Cannot open the experience", copy);
        }

        // ---- scene selection -------------------------------------------------

        /// <summary>
        /// Load the scene the payload names, falling back to the scene this
        /// component was configured with when the payload names nothing the
        /// build contains — a backend typo must not blank the headset.
        /// </summary>
        void LoadExperienceScene()
        {
            var requested = ResolveSceneName();
            if (!EnvironmentLoader.LoadEnvironment(requested) &&
                !string.Equals(requested, nextScene, StringComparison.Ordinal))
            {
                Debug.LogWarning(
                    LogPrefix + "Falling back to the configured scene '" +
                    nextScene + "'.");
                EnvironmentLoader.LoadEnvironment(nextScene);
            }
        }

        string ResolveSceneName()
        {
            var payload = ExperienceContent.Current;
            var requested = payload != null ? payload.SceneIdentifier : null;
            if (string.IsNullOrEmpty(requested)) return nextScene;

            if (Application.CanStreamedLevelBeLoaded(requested)) return requested;

            Debug.LogWarning(
                LogPrefix + "Experience asks for scene '" + requested +
                "' which is not in the build; using '" + nextScene + "'.");
            return nextScene;
        }

        // ---- deep links -------------------------------------------------------

        void HandleInitialDeepLink()
        {
            // Cold start: Android delivers the intent URL here. Editor play
            // mode yields a file:// URL, so the scheme check keeps noise out.
            var url = Application.absoluteURL;
            if (IsLaunchUrl(url)) HandleLaunchUrl(url);
        }

        void OnDeepLinkActivated(string url)
        {
            // Warm start: the app was already running (launchMode=singleTask).
            if (IsLaunchUrl(url)) HandleLaunchUrl(url);
        }

        static bool IsLaunchUrl(string url)
        {
            return !string.IsNullOrEmpty(url)
                   && url.StartsWith(LaunchData.Scheme + ":", StringComparison.OrdinalIgnoreCase);
        }

        void HandleLaunchUrl(string url)
        {
            LaunchData data;
            string error;
            if (!DeepLinkManager.TryHandle(url, out data, out error))
            {
                // A rejected link during a live session would otherwise do
                // nothing at all — the reader tapped in the phone app and
                // the headset stayed silent.
                Debug.LogWarning(LogPrefix + "Launch link rejected: " + error);
                ShowErrorWhenReady("Launch link rejected", error);
                return;
            }

            // LaunchData.ToString masks the token; the raw URL is never
            // logged because it carries the token in the query string.
            Debug.Log(LogPrefix + "Launch link accepted: " + data);

            if (auth == null)
            {
                // BootRoutine has not connected yet; ConnectToBackend reads
                // DeepLinkManager.LastLaunch when it gets there.
                return;
            }

            StartCoroutine(RelaunchRoutine(data));
        }

        /// <summary>
        /// A link arriving while the app is already running: exchange it,
        /// then reload the environment so the spawners rebuild from the
        /// freshly applied payload (a cold start needs no reload — the
        /// scene has not been chosen yet).
        /// </summary>
        IEnumerator RelaunchRoutine(LaunchData data)
        {
            if (!loadMuseumOnStart) yield break;

            yield return ExchangeAndApply(data);

            if (!lastExchangeSucceeded) yield break;

            if (EnvironmentLoader.Instance != null &&
                EnvironmentLoader.Instance.Current != null)
            {
                LoadExperienceScene();
            }
        }

        // ---- progress ---------------------------------------------------------

        /// <summary>
        /// Report a newly opened artifact. Fired by
        /// <see cref="ExperienceContent"/> — never called by scene scripts
        /// themselves — and only when a session token is actually held, so
        /// local-data runs make no requests at all.
        /// </summary>
        void OnArtifactViewed(int artifactId)
        {
            if (apiClient == null || auth == null || !auth.HasSession) return;

            var viewed = ExperienceContent.ViewedArtifactIds();
            if (viewed.Length == 0) return;

            StartCoroutine(apiClient.RecordProgress(null, viewed, OnProgressRecorded));
        }

        void OnProgressRecorded(ApiResult result)
        {
            // Progress is best-effort by design: a headset walking out of
            // Wi-Fi range mid-visit must not surface an error for it.
            if (!result.Ok)
            {
                Debug.LogWarning(
                    LogPrefix + "Progress not recorded (" + result.ErrorCode + ").");
            }
        }

        // ---- error panel ------------------------------------------------------

        /// <summary>
        /// Show <see cref="VrErrorPanel"/> now when an environment is
        /// already up, otherwise queue it for the moment one is — a launch
        /// failure happens before the museum loads, and the reader should
        /// meet the explanation inside the gallery, not in a void.
        /// </summary>
        void ShowErrorWhenReady(string title, string message)
        {
            if (HeritageEnvironment.Active != null)
            {
                VrErrorPanel.Show(title, message);
                return;
            }

            pendingErrorTitle = title;
            pendingErrorMessage = message;
            hasPendingError = true;

            EnvironmentLoader.EnvironmentReady -= OnEnvironmentReady;
            EnvironmentLoader.EnvironmentReady += OnEnvironmentReady;
        }

        void OnEnvironmentReady(HeritageEnvironment environment)
        {
            EnvironmentLoader.EnvironmentReady -= OnEnvironmentReady;
            if (!hasPendingError) return;

            hasPendingError = false;
            VrErrorPanel.Show(pendingErrorTitle, pendingErrorMessage);
            pendingErrorTitle = null;
            pendingErrorMessage = null;
        }

        // ---- XR ---------------------------------------------------------------

        /// <summary>
        /// True when the headset reports both position and rotation tracking.
        /// </summary>
        public static bool IsHeadTracked()
        {
            var device = InputDevices.GetDeviceAtXRNode(XRNode.Head);
            if (!device.isValid) return false;

            InputTrackingState state;
            return device.TryGetFeatureValue(CommonUsages.trackingState, out state)
                   && (state & (InputTrackingState.Position | InputTrackingState.Rotation)) != 0;
        }
    }
}
