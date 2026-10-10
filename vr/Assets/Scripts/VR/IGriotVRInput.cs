using System;

namespace Griot.VR
{
    /// <summary>
    /// The two gestures every Griot VR platform shares: "activate what I am
    /// looking at" and "recenter my view".
    /// </summary>
    /// <remarks>
    /// Headset code today drives interaction through XRI's own input actions
    /// (the <c>&lt;XRController&gt;…/trigger</c> bindings in
    /// <see cref="VRPlayerController"/>); those are untouched. This interface
    /// exists so shared systems have a platform-neutral way to observe the
    /// same intent without naming XR devices — mobile implements it with
    /// screen taps, the headset with either trigger.
    /// </remarks>
    public interface IGriotVRInput
    {
        /// <summary>True while a usable device binds this input.</summary>
        bool IsAvailable { get; }

        /// <summary>Raised once per "select" gesture (screen tap, trigger).</summary>
        event Action SelectPressed;

        /// <summary>
        /// Raised once per "recenter" gesture (screen double-tap). The
        /// headset implementation never raises it: recentering there belongs
        /// to the XR runtime.
        /// </summary>
        event Action RecenterRequested;
    }
}
