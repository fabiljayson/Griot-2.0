using UnityEngine;
using UnityEngine.XR.Interaction.Toolkit.Locomotion.Teleportation;

namespace Griot.VR
{
    /// <summary>
    /// Makes a collider-led surface teleportable: adds an XRI
    /// <c>TeleportationArea</c> at runtime with comfort-safe orientation
    /// matching.
    /// </summary>
    /// <remarks>
    /// The component is added at runtime so the scene YAML never references
    /// package script GUIDs (see <see cref="GriotInteractable"/> for the same
    /// rationale). The provider reference is deliberately left unset — XRI's
    /// area locates the rig's <c>TeleportationProvider</c> itself, which keeps
    /// this component working no matter where the rig was spawned.
    /// </remarks>
    [DisallowMultipleComponent]
    public sealed class GriotTeleportArea : MonoBehaviour
    {
        const string LogPrefix = "[GriotVR] ";

        void Awake()
        {
            if (GetComponent<Collider>() == null)
            {
                // A TeleportationArea without a collider can never be hit by
                // the teleport ray, so adding one would only hide the mistake.
                Debug.LogWarning(
                    LogPrefix + name + " has no Collider; TeleportationArea not added.");
                return;
            }

            if (GetComponent<TeleportationArea>() != null) return;

            var area = gameObject.AddComponent<TeleportationArea>();

            // World Space Up keeps the user's facing through the teleport and
            // never rotates the rig unexpectedly — the comfort default for a
            // museum floor. Target Up And Forward would re-aim the player.
            area.matchOrientation = MatchOrientation.WorldSpaceUp;
        }
    }
}
