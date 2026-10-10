using System;
using UnityEngine;
using UnityEngine.XR.Interaction.Toolkit.Locomotion.Teleportation;

namespace Griot.VR
{
    /// <summary>
    /// Griot-facing front door to XRI teleportation: readiness checks, a
    /// programmatic teleport for tests and future anchored destinations, and
    /// an event later scenes can hook (audio, haptics) without touching XRI
    /// types themselves.
    /// </summary>
    /// <remarks>
    /// Point-and-teleport for the user is entirely XRI's (the rig's teleport
    /// interactors, Teleportation Provider and Teleportation Areas); this
    /// component exists so gameplay code has one stable Griot API instead of
    /// reaching into the toolkit. The provider is looked up lazily because the
    /// rig may be created after this component awakes.
    /// </remarks>
    [DisallowMultipleComponent]
    public sealed class VRTeleportController : MonoBehaviour
    {
        const string LogPrefix = "[GriotVR] ";

        [SerializeField] TeleportationProvider provider;

        bool warnedMissingProvider;

        /// <summary>The XRI provider used for teleport requests, or null.</summary>
        public TeleportationProvider Provider
        {
            get
            {
                if (provider == null)
                {
                    provider = FindAnyObjectByType<TeleportationProvider>();
                }

                if (provider == null && !warnedMissingProvider)
                {
                    warnedMissingProvider = true;
                    Debug.LogWarning(
                        LogPrefix + "No TeleportationProvider found — programmatic " +
                        "teleporting is disabled. Run 'Tools > Griot > Setup " +
                        "Locomotion and Interaction' in the Editor to install the rig.");
                }

                return provider;
            }
        }

        /// <summary>True when teleport requests can be queued.</summary>
        public bool IsReady => Provider != null;

        /// <summary>Raised after a teleport request was queued successfully.</summary>
        public event Action<TeleportRequest> TeleportQueued;

        /// <summary>
        /// Teleports the rig to a world position, keeping the user's facing.
        /// Returns false when no provider is available or the request was
        /// rejected (another locomotion provider is mid-move).
        /// </summary>
        public bool TeleportTo(Vector3 worldPosition)
        {
            return TeleportTo(worldPosition, MatchOrientation.WorldSpaceUp);
        }

        /// <inheritdoc cref="TeleportTo(Vector3)"/>
        public bool TeleportTo(Vector3 worldPosition, MatchOrientation orientation)
        {
            var activeProvider = Provider;
            if (activeProvider == null) return false;

            var request = new TeleportRequest
            {
                destinationPosition = worldPosition,
                destinationRotation = Quaternion.identity,
                matchOrientation = orientation,
            };

            if (!activeProvider.QueueTeleportRequest(request))
            {
                Debug.LogWarning(
                    LogPrefix + "Teleport request to " + worldPosition +
                    " was rejected; a locomotion transition is already running.");
                return false;
            }

            TeleportQueued?.Invoke(request);
            return true;
        }
    }
}
