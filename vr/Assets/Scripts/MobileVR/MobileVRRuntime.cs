using System.Collections;
using UnityEngine;

namespace Griot.VR.MobileVR
{
    /// <summary>
    /// The phone runtime: verify the sensors, set the frame budget, build
    /// the <see cref="MobileVRRig"/>, then — when the museum scene is up —
    /// lay out the navigation markers and switch the gaze on.
    /// </summary>
    /// <remarks>
    /// Owns everything mobile-only so the shared bootstrap stays ignorant
    /// of the phone: <see cref="GriotVrBootstrap"/> only calls
    /// <see cref="Initialize"/> where it used to wait for XR, and reads
    /// <see cref="BootProblem"/> where it used to have none. This runtime
    /// never touches <c>XRGeneralSettings</c>, <c>XROrigin</c> or
    /// <c>XRNode</c> — nothing here can start an XR loader.
    /// </remarks>
    public sealed class MobileVRRuntime : IGriotVRRuntime
    {
        const string LogPrefix = "[GriotVR] ";
        const float ArtifactSpawnWaitSeconds = 5f;

        readonly MobileVRPerformanceSettings performance;

        MobileVRRig rig;

        public GriotVRRuntimeMode Mode => GriotVRRuntimeMode.MobileVR;

        public Transform PlacementRoot { get; private set; }

        public string BootProblem { get; private set; }

        /// <summary>The rig's tap gestures; null until <see cref="Initialize"/> built it.</summary>
        public IGriotVRInput Input => rig != null ? rig.Input : null;

        public MobileVRRuntime(MobileVRPerformanceSettings performanceSettings)
        {
            performance = performanceSettings;
        }

        public IEnumerator Initialize()
        {
            var capability = MobileVRCapabilityChecker.Check();

            MobileVRPerformanceSettings.Resolve(performance).Apply();

            rig = MobileVRRig.Create();
            PlacementRoot = rig.transform;

            EnvironmentLoader.EnvironmentReady -= OnEnvironmentReady;
            EnvironmentLoader.EnvironmentReady += OnEnvironmentReady;

            if (!capability.IsHeadTrackingCapable)
            {
                // Diagnostic mode: the rig stays a static forward view so
                // panels remain reachable, and the bootstrap surfaces this
                // copy through its error panel.
                BootProblem = capability.Problem;
            }

            Debug.Log(
                LogPrefix + "Mobile VR runtime ready: side-by-side stereo, head tracking " +
                (capability.IsHeadTrackingCapable
                    ? (Application.isEditor ? "simulated (EDITOR SIMULATION)" : "gyroscope")
                    : "static (diagnostic)") + ".");
            yield break;
        }

        public void Shutdown()
        {
            EnvironmentLoader.EnvironmentReady -= OnEnvironmentReady;
        }

        void OnEnvironmentReady(HeritageEnvironment environment)
        {
            if (rig == null) return;

            rig.ShowReticle();
            rig.StartCoroutine(LayoutNavigationWhenArtifactsReady(environment));
        }

        /// <summary>
        /// <see cref="EnvironmentLoader"/> raises its event from
        /// <c>SceneManager.sceneLoaded</c>, which fires before
        /// <c>ArtifactSpawner.Start</c> has built its interactables — so the
        /// layout waits (a few frames, capped) for the first artifact to
        /// exist rather than racing the spawners.
        /// </summary>
        IEnumerator LayoutNavigationWhenArtifactsReady(HeritageEnvironment environment)
        {
            var waited = 0f;
            while (waited < ArtifactSpawnWaitSeconds)
            {
                if (Object.FindObjectsByType<ArtifactInteractable>(
                        FindObjectsInactive.Exclude).Length > 0)
                {
                    MobileVRNavigationPoint.AutoLayout(environment);
                    yield break;
                }

                waited += Time.unscaledDeltaTime;
                yield return null;
            }

            Debug.LogWarning(
                LogPrefix + "No artifacts appeared within " + ArtifactSpawnWaitSeconds +
                " s; mobile navigation markers skipped.");
        }
    }
}
