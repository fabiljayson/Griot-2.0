using UnityEngine;

namespace Griot.VR.MobileVR
{
    /// <summary>
    /// Frame pacing for the phone: the Infinix HOT 60i drives two eye
    /// viewports, so 60 Hz with vsync off keeps the pipeline predictable
    /// where the headset path asks for 72 Hz.
    /// </summary>
    /// <remarks>
    /// §25 of the Mobile VR spec: frame rate is a per-runtime decision.
    /// Created in code with safe defaults, or authored as an asset
    /// (Tools/Griot menu not required — CreateAssetMenu below) and dropped
    /// into the field of <see cref="MobileVRRuntime"/> for on-device tuning
    /// without a rebuild of the logic. On Android vsync is advisory; the
    /// explicit target is what Unity's frame pacing honours.
    /// </remarks>
    [CreateAssetMenu(fileName = "MobileVRPerformanceSettings", menuName = "Griot/Mobile VR Performance Settings")]
    public sealed class MobileVRPerformanceSettings : ScriptableObject
    {
        [SerializeField, Range(30, 120)] int targetFrameRate = 60;
        [SerializeField, Range(0, 4)] int vSyncCount;
        [SerializeField] bool keepScreenAwake = true;

        public int TargetFrameRate => Mathf.Clamp(targetFrameRate, 30, 120);
        public int VSyncCount => Mathf.Max(vSyncCount, 0);
        public bool KeepScreenAwake => keepScreenAwake;

        public void Apply()
        {
            Application.targetFrameRate = TargetFrameRate;
            QualitySettings.vSyncCount = VSyncCount;
            if (KeepScreenAwake) Screen.sleepTimeout = SleepTimeout.NeverSleep;

            Debug.Log(
                "[GriotVR] Mobile performance: target " + TargetFrameRate +
                " fps, vsync " + VSyncCount + ".");
        }

        /// <summary>Defaults for builds that never author the asset.</summary>
        public static MobileVRPerformanceSettings CreateDefault()
        {
            var settings = CreateInstance<MobileVRPerformanceSettings>();
            settings.hideFlags = HideFlags.DontSave;
            return settings;
        }

        public static MobileVRPerformanceSettings Resolve(MobileVRPerformanceSettings assigned)
        {
            return assigned != null ? assigned : CreateDefault();
        }
    }
}
