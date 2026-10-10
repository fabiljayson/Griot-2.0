using System.Collections;
using Unity.XR.CoreUtils;
using UnityEngine;
using UnityEngine.XR.Management;

namespace Griot.VR
{
    /// <summary>
    /// The headset path: wait for XR Plug-in Management to initialise the
    /// OpenXR loader, keep the scene's <see cref="XROrigin"/> alive across
    /// the single-scene loads that follow, and expose it as the root
    /// <see cref="EnvironmentLoader"/> places at the spawn point.
    /// </summary>
    /// <remarks>
    /// This is the pre-Milestone-7 bootstrap logic moved verbatim — the
    /// shared systems in <see cref="GriotVrBootstrap"/> (deep link, token
    /// exchange, payload, scene selection, progress, error panel) never
    /// changed and never see this class. Nothing here starts XR on a phone:
    /// a build without the OpenXR loader simply logs the same warnings it
    /// always did.
    /// </remarks>
    public sealed class HeadsetVRRuntime : IGriotVRRuntime
    {
        const float XrInitTimeoutSeconds = 10f;
        const string LogPrefix = "[GriotVR] ";

        public GriotVRRuntimeMode Mode => GriotVRRuntimeMode.HeadsetVR;

        public Transform PlacementRoot { get; private set; }

        /// <summary>Never blocks: a missing rig was always a log error, not a boot stop.</summary>
        public string BootProblem => null;

        public IGriotVRInput Input { get; }

        public HeadsetVRRuntime()
        {
            Input = new HeadsetVRInput();
        }

        public IEnumerator Initialize()
        {
            // Moved out of the bootstrap Awake so each runtime owns its
            // frame pacing: 72 Hz here, the mobile performance settings on
            // the phone (§25 of the Mobile VR spec).
            Application.targetFrameRate = GriotVrBootstrap.PreferredRefreshRate;

            yield return WaitForXr();

            var origin = Object.FindAnyObjectByType<XROrigin>();
            if (origin == null)
            {
                Debug.LogError(
                    LogPrefix + "No XR Origin found in the Bootstrap scene. " +
                    "In the Unity Editor run 'Tools > Griot > Setup VR Project'.");
            }
            else
            {
                // The rig has to outlive the single-scene loads that follow.
                Object.DontDestroyOnLoad(origin.gameObject);
                PlacementRoot = origin.transform;
                Debug.Log(LogPrefix + "XR Origin ready. Head tracked: " + GriotVrBootstrap.IsHeadTracked() + ".");
            }
        }

        public void Shutdown()
        {
        }

        static IEnumerator WaitForXr()
        {
            XRManagerSettings manager =
                XRGeneralSettings.Instance != null ? XRGeneralSettings.Instance.Manager : null;

            if (manager == null)
            {
                Debug.LogWarning(
                    LogPrefix + "XR Plug-in Management is not configured; " +
                    "skipping the XR initialisation wait.");
                yield break;
            }

            var waited = 0f;
            while (!manager.isInitializationComplete && waited < XrInitTimeoutSeconds)
            {
                waited += Time.unscaledDeltaTime;
                yield return null;
            }

            if (!manager.isInitializationComplete)
            {
                Debug.LogError(
                    LogPrefix + "XR initialisation timed out. Check that OpenXR is " +
                    "enabled for Android in Project Settings > XR Plug-in Management.");
            }
        }
    }
}
