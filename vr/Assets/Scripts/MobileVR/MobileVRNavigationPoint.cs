using UnityEngine;

namespace Griot.VR.MobileVR
{
    /// <summary>
    /// A gaze-and-tap teleport spot: a floating ring the reader can look at
    /// to hop to a standing position in front of an artifact. The whole
    /// museum is reachable this way — mobile VR has no thumbstick and no
    /// continuous locomotion (§9 of the Mobile VR spec).
    /// </summary>
    /// <remarks>
    /// <para>
    /// The component doubles as marker and trigger: its own (trigger)
    /// collider is the gaze hit target, its child ring is the visual. The
    /// visual is only built in mobile mode — in a headset build this
    /// component is inert, so scenes stay clean for both runtimes.
    /// </para>
    /// <para>
    /// <see cref="AutoLayout"/> derives a point per spawned
    /// <see cref="ArtifactInteractable"/> after the environment is ready,
    /// so authoring stays zero-touch: new pedestals get new standing spots
    /// automatically. Manually placed points (scene-authored) keep their
    /// transform rotation as the post-teleport facing.
    /// </para>
    /// </remarks>
    [DisallowMultipleComponent]
    public sealed class MobileVRNavigationPoint : MonoBehaviour
    {
        [Tooltip("Where the reader stands after teleporting. Falls back to this transform's XZ when empty.")]
        [SerializeField] Transform destination;

        [Tooltip("Rotate the rig to this marker's facing after the teleport (markers face their artifact).")]
        [SerializeField] bool rotateToMarker = true;

        static readonly int BaseColorProperty = Shader.PropertyToID("_BaseColor");
        static readonly int ColorProperty = Shader.PropertyToID("_Color");

        static bool layoutCompleted;

        Renderer ringRenderer;
        MaterialPropertyBlock tintBlock;
        int tintPropertyId;
        bool hasTintProperty;
        bool hovered;

        public Vector3 DestinationPosition =>
            destination != null ? destination.position : transform.position;

        public Quaternion DestinationRotation =>
            rotateToMarker ? transform.rotation : Quaternion.identity;

        public bool RotateToMarker => rotateToMarker;

        void Awake()
        {
            // The gaze ray needs a collider; a trigger keeps the marker
            // from blocking physics movement and from registering as an
            // obstacle hit for other systems.
            if (!TryGetComponent<Collider>(out _))
            {
                var sphere = gameObject.AddComponent<SphereCollider>();
                sphere.isTrigger = true;
                sphere.radius = 0.22f;
            }

            BuildVisual();
        }

        public void Configure(Transform standingSpot, bool faceMarkerForward)
        {
            destination = standingSpot;
            rotateToMarker = faceMarkerForward;
        }

        public void SetGazeHovered(bool value)
        {
            if (hovered == value) return;
            hovered = value;
            ApplyTint(hovered ? MobileVRReticle.HoverColour : MobileVRReticle.IdleColour);
        }

        /// <summary>The rig jump. Instant by design — comfort choice of §9.</summary>
        public void Teleport(MobileVRRig rig)
        {
            if (rig == null) return;
            rig.TeleportTo(DestinationPosition, rotateToMarker ? (Quaternion?)DestinationRotation : null);
        }

        void BuildVisual()
        {
            var go = new GameObject("Marker Ring");
            go.transform.SetParent(transform, false);

            var filter = go.AddComponent<MeshFilter>();
            filter.sharedMesh = BuildRingMesh();

            ringRenderer = go.AddComponent<MeshRenderer>();
            ringRenderer.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            ringRenderer.receiveShadows = false;

            var shader =
                (UnityEngine.Rendering.GraphicsSettings.currentRenderPipeline != null
                    ? Shader.Find("Universal Render Pipeline/Unlit")
                    : null) ??
                Shader.Find("Unlit/Color") ??
                Shader.Find("Sprites/Default");

            if (shader != null)
            {
                var material = new Material(shader);
                ringRenderer.sharedMaterial = material;
                if (material.HasProperty(BaseColorProperty))
                {
                    tintPropertyId = BaseColorProperty;
                    hasTintProperty = true;
                }
                else if (material.HasProperty(ColorProperty))
                {
                    tintPropertyId = ColorProperty;
                    hasTintProperty = true;
                }
            }

            tintBlock = new MaterialPropertyBlock();
            ApplyTint(MobileVRReticle.IdleColour);
        }

        void ApplyTint(Color colour)
        {
            if (!hasTintProperty || ringRenderer == null) return;
            ringRenderer.GetPropertyBlock(tintBlock);
            tintBlock.SetColor(tintPropertyId, colour);
            ringRenderer.SetPropertyBlock(tintBlock);
        }

        static Mesh BuildRingMesh()
        {
            const float outerRadius = 0.11f;
            const float innerRadius = 0.085f;
            const int segments = 32;

            var vertices = new Vector3[segments * 2];
            var normals = new Vector3[segments * 2];
            var triangles = new int[segments * 6];

            for (var i = 0; i < segments; i++)
            {
                var angle = i * Mathf.PI * 2f / segments;
                var cos = Mathf.Cos(angle);
                var sin = Mathf.Sin(angle);
                vertices[i] = new Vector3(cos * outerRadius, sin * outerRadius, 0f);
                vertices[i + segments] = new Vector3(cos * innerRadius, sin * innerRadius, 0f);
                normals[i] = Vector3.back;
                normals[i + segments] = Vector3.back;
            }

            for (var i = 0; i < segments; i++)
            {
                var outer = i;
                var inner = i + segments;
                var outerNext = (i + 1) % segments;
                var innerNext = (i + 1) % segments + segments;

                var t = i * 6;
                triangles[t] = outer;
                triangles[t + 1] = inner;
                triangles[t + 2] = innerNext;
                triangles[t + 3] = outer;
                triangles[t + 4] = innerNext;
                triangles[t + 5] = outerNext;
            }

            var mesh = new Mesh
            {
                name = "Navigation Marker Ring",
                vertices = vertices,
                normals = normals,
                triangles = triangles,
            };
            mesh.RecalculateBounds();
            return mesh;
        }

        // ---- derived layout ------------------------------------------------

        /// <summary>
        /// One standing spot per artifact: 1.5 m back along the spawn→
        /// artifact line, marker ring at head height over the spot facing
        /// the artifact. Runs once per session, after the spawners have
        /// built their interactables (sceneLoaded fires before Start, so
        /// <paramref name="environment"/>-ready alone is too early — the
        /// caller waits a frame or two).
        /// </summary>
        public static void AutoLayout(HeritageEnvironment environment)
        {
            if (layoutCompleted || environment == null) return;

            var artifacts = FindObjectsByType<ArtifactInteractable>(FindObjectsInactive.Exclude);
            if (artifacts.Length == 0) return;

            layoutCompleted = true;

            var spawn = environment.PlayerSpawnPosition;
            foreach (var artifact in artifacts)
            {
                var artifactPosition = artifact.transform.position;
                var toArtifact = artifactPosition - spawn;
                toArtifact.y = 0f;
                if (toArtifact.sqrMagnitude < 0.04f) continue; // standing on it already

                var direction = toArtifact.normalized;

                var standing = artifactPosition - direction * 1.5f;
                standing.y = spawn.y;

                var markerPosition = standing;
                markerPosition.y = spawn.y + 1.3f;

                var facing = Quaternion.LookRotation(
                    new Vector3(
                        artifactPosition.x - markerPosition.x,
                        0f,
                        artifactPosition.z - markerPosition.z));

                var markerGo = new GameObject("Navigation: " + artifact.name);
                markerGo.transform.SetPositionAndRotation(markerPosition, facing);
                markerGo.transform.SetParent(environment.transform, true);

                var spotGo = new GameObject("Standing Spot");
                spotGo.transform.SetPositionAndRotation(standing, facing);
                spotGo.transform.SetParent(markerGo.transform, true);

                var point = markerGo.AddComponent<MobileVRNavigationPoint>();
                point.Configure(spotGo.transform, true);
            }

            Debug.Log(
                "[GriotVR] Mobile navigation laid out for " + artifacts.Length +
                " artifacts in " + environment.DisplayName + ".");
        }

        // Domain-reload-off: static layout latch must not survive a play.
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
        static void ResetStatics()
        {
            layoutCompleted = false;
        }
    }
}
