using UnityEngine;

namespace Griot.VR.Network
{
    /// <summary>
    /// Where the app finds the Griot API and how it behaves there. Created
    /// through <i>Assets → Create → Griot → API Config</i> and assigned to
    /// the bootstrap component; without an asset the bootstrap uses
    /// <see cref="CreateRuntimeDefault"/>.
    /// </summary>
    /// <remarks>
    /// The asset holds a base URL and development switches only — no key,
    /// no secret, nothing that identifies a user. The only credential this
    /// app ever holds is the launch token from the deep link, which lives
    /// in memory for the length of one exchange and is then replaced by the
    /// session JWT in <see cref="Authentication.VRTokenStore"/>.
    /// </remarks>
    [CreateAssetMenu(fileName = "GriotApiConfig", menuName = "Griot/API Config")]
    public sealed class GriotApiConfig : ScriptableObject
    {
        /// <summary>Deployed API root, used when no asset is assigned.</summary>
        public const string DefaultBaseUrl = "https://africanteller.org/api";

        [Tooltip("API root including the /api prefix, e.g. https://africanteller.org/api")]
        [SerializeField] string baseUrl = DefaultBaseUrl;

        [Tooltip("Seconds before an HTTP request is abandoned.")]
        [SerializeField, Range(3, 60)] int requestTimeoutSeconds = 10;

        [Tooltip("Serve development stub payloads instead of calling the API.")]
        [SerializeField] bool useMockApi;

        /// <summary>Base URL, trailing slash removed. Falls back to the deployed API.</summary>
        public string BaseUrl
        {
            get
            {
                return string.IsNullOrEmpty(baseUrl) ? DefaultBaseUrl : baseUrl.TrimEnd('/');
            }
        }

        public int RequestTimeoutSeconds => Mathf.Clamp(requestTimeoutSeconds, 3, 60);

        public bool UseMockApi => useMockApi;

        /// <summary>
        /// A config used when no asset is assigned to the bootstrap:
        /// the deployed API on device, and the mock stub in the Editor —
        /// so pressing Play exercises the whole pipeline without ever
        /// reaching production, while a headset build always talks to the
        /// real backend unless a developer deliberately assigns an asset.
        /// </summary>
        public static GriotApiConfig CreateRuntimeDefault()
        {
            var config = CreateInstance<GriotApiConfig>();
            config.hideFlags = HideFlags.DontSave;
            config.name = "GriotApiConfig (runtime default)";
            config.useMockApi = Application.isEditor;
            return config;
        }

        /// <summary>
        /// Always the mock stub, regardless of platform: the
        /// <c>USE_MOCK_API</c> validation build of the phone APK (§26 of the
        /// Mobile VR spec) so on-device mobile VR testing never reaches the
        /// deployed API.
        /// </summary>
        public static GriotApiConfig CreateMockDefault()
        {
            var config = CreateInstance<GriotApiConfig>();
            config.hideFlags = HideFlags.DontSave;
            config.name = "GriotApiConfig (mock, USE_MOCK_API)";
            config.useMockApi = true;
            return config;
        }
    }
}
