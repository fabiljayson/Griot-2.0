using UnityEngine;

namespace Griot.VR.MobileVR
{
    /// <summary>
    /// What a device must have for the mobile VR experience: a gyroscope
    /// for head tracking, an accelerometer as Unity's sensor fallback, and
    /// a landscape-safe screen. Checked once at boot before the rig is
    /// built, so an incapable device gets an explanation instead of a
    /// frozen picture.
    /// </summary>
    /// <remarks>
    /// A phone without a gyroscope still boots into the museum —
    /// <see cref="IsHeadTrackingCapable"/> is false and the rig stays
    /// diagnostic (static forward view, UI panels reachable), with the
    /// problem surfaced through <see cref="IGriotVRRuntime.BootProblem"/>.
    /// The Editor is always "capable" because it simulates the head with
    /// the mouse (§32 of the Mobile VR spec).
    /// </remarks>
    public static class MobileVRCapabilityChecker
    {
        public const string GyroscopeRequiredMessage =
            "GriotVR requires a gyroscope for VR head tracking.";

        public struct Result
        {
            public bool Gyroscope;
            public bool Accelerometer;
            public bool LandscapeSafe;
            public bool IsHeadTrackingCapable;
            public string Problem;
        }

        public static Result Check()
        {
            var gyro = SystemInfo.supportsGyroscope;
            var accel = SystemInfo.supportsAccelerometer;
            var landscape = Screen.width >= Screen.height;

            // Editor: mouse-driven simulation counts as capable.
            var capable = Application.isEditor || gyro;

            var result = new Result
            {
                Gyroscope = gyro,
                Accelerometer = accel,
                LandscapeSafe = landscape,
                IsHeadTrackingCapable = capable,
                Problem = capable ? null : GyroscopeRequiredMessage,
            };

            Debug.Log(
                "[GriotVR] Mobile VR capability: gyro=" + gyro +
                ", accelerometer=" + accel +
                ", orientation=" + Screen.orientation +
                (capable ? "." : " — " + GyroscopeRequiredMessage));

            return result;
        }
    }
}
