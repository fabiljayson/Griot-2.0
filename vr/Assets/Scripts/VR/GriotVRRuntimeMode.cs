namespace Griot.VR
{
    /// <summary>
    /// Which VR runtime <see cref="GriotVrBootstrap"/> boots: the phone-based
    /// mobile viewer (SHINECON + gyro) or the existing OpenXR headset path.
    /// </summary>
    /// <remarks>
    /// <see cref="Auto"/> decides at boot: an active XR session wins, else a
    /// gyroscope means a phone, else the headset path (the historic default,
    /// which is also what the desktop Editor resolves to). Forcing a value in
    /// the Bootstrap inspector makes the choice deterministic — "Mobile VR"
    /// is how the Editor simulates the phone build.
    /// </remarks>
    public enum GriotVRRuntimeMode
    {
        Auto = 0,
        MobileVR = 1,
        HeadsetVR = 2,
    }
}
