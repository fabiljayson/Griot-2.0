using System.Collections;
using UnityEngine;

namespace Griot.VR
{
    /// <summary>
    /// Platform slice of the boot sequence: everything that differs between
    /// a phone in a SHINECON viewer and an OpenXR headset, and nothing else.
    /// </summary>
    /// <remarks>
    /// The shared systems (deep links, token exchange, experience payload,
    /// scene loading, errors, progress) live in <see cref="GriotVrBootstrap"/>
    /// and never see this interface. What lives behind it is exactly what the
    /// two platforms do differently: XR initialisation versus building a
    /// stereo phone rig, and the rig transform that
    /// <see cref="EnvironmentLoader"/> moves to the environment's spawn point.
    /// No shared code should cast to a concrete implementation — the point of
    /// the abstraction is that it eventually covers other headsets too.
    /// </remarks>
    public interface IGriotVRRuntime
    {
        /// <summary>The concrete mode this runtime provides.</summary>
        GriotVRRuntimeMode Mode { get; }

        /// <summary>
        /// Root transform <see cref="EnvironmentLoader"/> places at the
        /// environment spawn — the XR Origin (headset) or the mobile rig.
        /// Null until <see cref="Initialize"/> has run.
        /// </summary>
        Transform PlacementRoot { get; }

        /// <summary>
        /// Boot-blocking problem for the reader to see (e.g. no gyroscope),
        /// or null when healthy. Read after <see cref="Initialize"/> finished.
        /// </summary>
        string BootProblem { get; }

        /// <summary>The platform's input abstraction (tap/double-tap, or triggers).</summary>
        IGriotVRInput Input { get; }

        /// <summary>Platform startup. Run by the bootstrap as a coroutine.</summary>
        IEnumerator Initialize();

        /// <summary>Tear down subscriptions when the bootstrap dies.</summary>
        void Shutdown();
    }
}
