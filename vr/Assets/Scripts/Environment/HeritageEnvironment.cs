using UnityEngine;

namespace Griot.VR
{
    /// <summary>
    /// Declares a scene as a loadable heritage environment and exposes the
    /// spawn point where the persistent XR rig should be placed on entry.
    /// </summary>
    /// <remarks>
    /// Exactly one of these lives at the root of every environment scene.
    /// <see cref="EnvironmentLoader"/> finds it after the scene load and moves
    /// the rig; keeping the spawn data in the scene (not in the loader) means
    /// an environment owns its own entrance geometry — repositioning a
    /// museum's doorway never touches bootstrap code.
    /// </remarks>
    [DisallowMultipleComponent]
    public sealed class HeritageEnvironment : MonoBehaviour
    {
        const string LogPrefix = "[GriotVR] ";

        [SerializeField] string environmentId = "";
        [SerializeField] string displayName = "";
        [SerializeField] Transform playerSpawn;

        /// <summary>
        /// The active environment, set while exactly one environment scene is
        /// loaded. Null in Bootstrap/Loading scenes.
        /// </summary>
        public static HeritageEnvironment Active { get; private set; }

        /// <summary>Stable machine id, e.g. <c>cameroon-heritage-museum</c>.</summary>
        public string EnvironmentId => environmentId;

        /// <summary>Human-readable title for logs and in-headset UI.</summary>
        public string DisplayName => displayName;

        /// <summary>World position of the player spawn. Falls back to this
        /// object's position when no spawn transform is assigned.</summary>
        public Vector3 PlayerSpawnPosition =>
            playerSpawn != null ? playerSpawn.position : transform.position;

        /// <summary>World rotation of the player spawn. Falls back to this
        /// object's rotation when no spawn transform is assigned.</summary>
        public Quaternion PlayerSpawnRotation =>
            playerSpawn != null ? playerSpawn.rotation : transform.rotation;

        void Awake()
        {
            // A mislabelled environment silently loads the player at the
            // world origin, which is impossible to diagnose from a headset —
            // complain loudly in the Console instead.
            if (string.IsNullOrEmpty(environmentId))
            {
                Debug.LogWarning(
                    LogPrefix + name + " has an empty environmentId.");
            }

            if (playerSpawn == null)
            {
                Debug.LogWarning(
                    LogPrefix + name + " has no playerSpawn; the rig will be " +
                    "placed at the environment's own transform.");
            }
        }

        void OnEnable()
        {
            Active = this;
        }

        void OnDisable()
        {
            // Scene unload order is not guaranteed, so only clear the
            // reference if it is still ours.
            if (Active == this) Active = null;
        }
    }
}
