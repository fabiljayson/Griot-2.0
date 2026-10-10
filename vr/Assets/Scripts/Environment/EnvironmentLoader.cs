using System;
using Unity.XR.CoreUtils;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace Griot.VR
{
    /// <summary>
    /// Persists on the bootstrap object, watches scene loads, and places the
    /// persistent XR rig at the loaded environment's spawn point.
    /// </summary>
    /// <remarks>
    /// The rig is moved on <see cref="SceneManager.sceneLoaded"/> rather than
    /// by the environment itself so environments stay passive data scenes —
    /// they never need a reference to the (bootstrap-owned) rig, and loading
    /// one additively later still works. Events fire after placement so
    /// subscribers always observe the rig at the spawn.
    /// </remarks>
    [DisallowMultipleComponent]
    [DefaultExecutionOrder(-50)]
    public sealed class EnvironmentLoader : MonoBehaviour
    {
        /// <summary>First playable environment (Bootstrap's nextScene).</summary>
        public const string CameroonMuseumSceneName = "CameroonHeritageMuseum";

        [SerializeField] bool placeRigOnLoad = true;

        const string LogPrefix = "[GriotVR] ";

        static EnvironmentLoader instance;

        /// <summary>Raised after an environment scene is active, the rig is
        /// placed, and <see cref="Current"/> is set.</summary>
        public static event Action<HeritageEnvironment> EnvironmentReady;

        /// <summary>Loader on the persistent bootstrap object, or null.</summary>
        public static EnvironmentLoader Instance => instance;

        /// <summary>Most recently loaded environment, or null.</summary>
        public HeritageEnvironment Current { get; private set; }

        void Awake()
        {
            if (instance != null && instance != this)
            {
                Debug.LogWarning(
                    LogPrefix + "Duplicate EnvironmentLoader on " + name +
                    "; ignoring this one.");
                return;
            }

            instance = this;
            SceneManager.sceneLoaded += OnSceneLoaded;
        }

        void OnDestroy()
        {
            if (instance != this) return;
            instance = null;
            SceneManager.sceneLoaded -= OnSceneLoaded;
        }

        void OnSceneLoaded(Scene scene, LoadSceneMode mode)
        {
            // Additive loads never replace the current environment.
            if (mode == LoadSceneMode.Additive) return;

            // Bootstrap and Loading have no HeritageEnvironment — that is a
            // valid state, not an error, so this is a quiet early-out.
            var environment = FindAnyObjectByType<HeritageEnvironment>(
                FindObjectsInactive.Include);
            if (environment == null)
            {
                Current = null;
                return;
            }

            Current = environment;

            if (placeRigOnLoad) PlaceRig(environment);

            EnvironmentReady?.Invoke(environment);
            Debug.Log(
                LogPrefix + "Environment ready: " + environment.DisplayName +
                " (" + environment.EnvironmentId + ").");
        }

        void PlaceRig(HeritageEnvironment environment)
        {
            // The active runtime owns which transform represents the
            // player: the XR Origin on the headset path, the procedural
            // mobile rig on the phone (§10 of the Mobile VR spec). The
            // XROrigin lookup remains only as a fallback so a scene loaded
            // before the bootstrap ran still places something sensible.
            var runtime = GriotVrBootstrap.ActiveRuntime;
            var root = runtime != null ? runtime.PlacementRoot : null;
            if (root == null)
            {
                var origin = FindAnyObjectByType<XROrigin>();
                if (origin == null)
                {
                    Debug.LogError(
                        LogPrefix + "No rig to place for " +
                        environment.DisplayName + ". Run 'Tools > Griot > Setup " +
                        "VR Project' in the Unity Editor.");
                    return;
                }
                root = origin.transform;
            }

            // Move the whole rig (never the camera directly) so head tracking
            // and comfort guarantees stay untouched — the core VR rule from
            // the project README.
            root.SetPositionAndRotation(
                environment.PlayerSpawnPosition,
                environment.PlayerSpawnRotation);
        }

        /// <summary>
        /// Loads an environment scene by name with a guard, so callers never
        /// trigger the default Unity "scene couldn't be loaded" error.
        /// </summary>
        /// <returns>True when the load was started.</returns>
        public static bool LoadEnvironment(string sceneName)
        {
            if (string.IsNullOrEmpty(sceneName) ||
                !Application.CanStreamedLevelBeLoaded(sceneName))
            {
                Debug.LogError(
                    LogPrefix + "Cannot load environment '" + sceneName +
                    "'. Check it is listed in File > Build Profiles.");
                return false;
            }

            SceneManager.LoadScene(sceneName);
            return true;
        }

        // Clears static state when Enter Play Mode disables domain reload,
        // otherwise a stale event subscriber survives between plays.
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
        static void ResetStatics()
        {
            instance = null;
            EnvironmentReady = null;
        }
    }
}
