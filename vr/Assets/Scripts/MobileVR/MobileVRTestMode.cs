namespace Griot.VR.MobileVR
{
    /// <summary>
    /// Compile-time switch that forces the phone build to talk to the local
    /// mock stub instead of the deployed API — the Android-side twin of the
    /// Editor's "mock in Editor" default.
    /// </summary>
    /// <remarks>
    /// The symbol <c>USE_MOCK_API</c> is toggled for Android from
    /// <c>Tools/Griot/Mobile VR: USE_MOCK_API (Android)</c>. When present it
    /// does two things at once (§26 of the Mobile VR spec): the bootstrap
    /// resolves <see cref="GriotApiConfig.CreateMockDefault"/>, and
    /// <see cref="Enabled"/> forces <see cref="GriotVRRuntimeMode.MobileVR"/>
    /// so a validation APK exercises the phone path regardless of what the
    /// headset-connected device would auto-detect. Shipping builds must not
    /// define the symbol.
    /// </remarks>
    public static class MobileVRTestMode
    {
        public const string DefineSymbol = "USE_MOCK_API";

        public static bool Enabled
        {
            get
            {
#if USE_MOCK_API
                return true;
#else
                return false;
#endif
            }
        }
    }
}
