using UnityEngine;
using UnityEngine.InputSystem;

namespace Griot.VR.MobileVR
{
    /// <summary>
    /// Turns the phone's gyroscope (or, in the Editor, the mouse) into the
    /// head rotation of the mobile rig's <c>HeadRoot</c>.
    /// </summary>
    /// <remarks>
    /// <para>
    /// The conversion follows Unity's documented recipe for
    /// <c>Input.gyro.attitude</c>: the sensor quaternion is re-mapped to
    /// Unity's left-handed space <c>(x, y, -z, -w)</c>, rotated by
    /// <c>Quaternion.Euler(90, 0, 0)</c> so the device's flat-lay frame
    /// becomes a camera frame, then converted into the rig root's local
    /// space. Holding the phone upright (portrait, screen toward the user)
    /// maps to looking straight ahead — the way the device sits in the
    /// SHINECON viewer.
    /// </para>
    /// <para>
    /// §13 of the Mobile VR spec: <see cref="orientationCompensation"/> is
    /// an authoring hook for on-device axis correction. It multiplies into
    /// the raw world rotation before localisation; leave it at identity
    /// unless a specific device reports a rotated frame (the default path
    /// is the tested conversion, not a compensation).
    /// </para>
    /// <para>
    /// The first sample captured after launch (or after
    /// <see cref="Recenter"/>) becomes "forward": the user never has to hold
    /// the phone at north. Smoothing is a time-constant Slerp — 0 means
    /// instant, values near 12 ≈ 80 ms settle which removes gyro jitter
    /// without visible lag.
    /// </para>
    /// </remarks>
    [DisallowMultipleComponent]
    public sealed class MobileVRHeadTracker : MonoBehaviour
    {
        static readonly Quaternion EarthToUnity = Quaternion.Euler(90f, 0f, 0f);

        [Tooltip("0 = instant; ~12 = ~80 ms smoothing that removes gyro jitter.")]
        [SerializeField, Range(0f, 30f)] float smoothing = 12f;

        [Tooltip("Authoring hook: multiplies the raw attitude before localisation. Identity unless a device reports a rotated frame.")]
        [SerializeField] Quaternion orientationCompensation = Quaternion.identity;

        [Tooltip("True = keep the horizon flat regardless of device roll (viewer holds the phone).")]
        [SerializeField] bool lockRoll;

        [Tooltip("Mouse degrees per pixel in the Editor simulation.")]
        [SerializeField, Range(0.05f, 1f)] float editorLookSensitivity = 0.25f;

        MobileVRRig rig;

        Quaternion zeroLocal = Quaternion.identity;
        Quaternion lastRawLocal = Quaternion.identity;
        bool zeroCaptured;

        float simulatedYaw;
        float simulatedPitch;

        /// <summary>True when the mouse drives the head (Editor or no gyro).</summary>
        public bool Simulated { get; private set; }

        public void Configure(MobileVRRig mobileRig)
        {
            rig = mobileRig;

            // §32: the Editor always simulates; a device without a gyro is
            // not simulated — its attitude stays identity (a static, still
            // head) which is exactly the diagnostic mode the capability
            // checker reports.
            Simulated = Application.isEditor;
            if (Simulated)
            {
                Debug.Log(
                    "[GriotVR] EDITOR SIMULATION: head tracking is mouse-driven; " +
                    "this is not sensor data.");
                return;
            }

            Input.gyro.enabled = true;
        }

        void LateUpdate()
        {
            if (rig == null) return;

            var target = Simulated ? SimulatedRotation() : GyroRotation();

            if (smoothing > 0f && Time.deltaTime > 0f)
                transform.localRotation = Quaternion.Slerp(
                    transform.localRotation, target, 1f - Mathf.Exp(-smoothing * Time.deltaTime));
            else
                transform.localRotation = target;
        }

        Quaternion GyroRotation()
        {
            var attitude = Input.gyro.attitude;
            var converted = new Quaternion(attitude.x, attitude.y, -attitude.z, -attitude.w);
            var world = EarthToUnity * (orientationCompensation * converted);
            var local = Quaternion.Inverse(rig.transform.rotation) * world;

            lastRawLocal = local;
            if (!zeroCaptured)
            {
                zeroLocal = local;
                zeroCaptured = true;
            }

            var target = Quaternion.Inverse(zeroLocal) * local;
            return lockRoll ? FlattenRoll(target) : target;
        }

        Quaternion SimulatedRotation()
        {
            var mouse = Mouse.current;
            if (mouse != null)
            {
                var delta = mouse.delta.ReadValue();
                simulatedYaw += delta.x * editorLookSensitivity;
                simulatedPitch = Mathf.Clamp(
                    simulatedPitch - delta.y * editorLookSensitivity, -85f, 85f);
            }

            return Quaternion.Euler(simulatedPitch, simulatedYaw, 0f);
        }

        /// <summary>
        /// Yaw/pitch only: extracts the look direction and rebuilds a
        /// horizon-flat rotation. Used when the viewer holds the phone with
        /// a roll the user does not intend as head roll.
        /// </summary>
        static Quaternion FlattenRoll(Quaternion rotation)
        {
            var forward = rotation * Vector3.forward;
            var yaw = Mathf.Atan2(forward.x, forward.z) * Mathf.Rad2Deg;
            var pitch = Mathf.Asin(Mathf.Clamp(forward.y, -1f, 1f)) * Mathf.Rad2Deg;
            return Quaternion.Euler(pitch, yaw, 0f);
        }

        /// <summary>
        /// Make the current pose the new forward. On device this re-anchors
        /// the captured gyro zero; in the simulation it zeroes the mouse
        /// accumulators. A gyro sample is always pending, so a static head
        /// is safe here too.
        /// </summary>
        public void Recenter()
        {
            if (Simulated)
            {
                simulatedYaw = 0f;
                simulatedPitch = 0f;
                return;
            }

            if (zeroCaptured) zeroLocal = lastRawLocal;
        }
    }
}
