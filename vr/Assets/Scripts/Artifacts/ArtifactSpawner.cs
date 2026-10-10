using Griot.VR.Network;
using UnityEngine;

namespace Griot.VR
{
    /// <summary>
    /// Places the first cultural artifact on a pedestal: retires the
    /// placeholder marker, builds a framed textile visual from primitives,
    /// and wires <see cref="ArtifactInteractable"/> and
    /// <see cref="ArtifactController"/> together.
    /// </summary>
    /// <remarks>
    /// The visual is constructed at runtime from cubes with project
    /// materials instead of a mesh import or hand-authored prefab instance —
    /// the real Ndop photography and models arrive with the Django artifact
    /// assets in a later milestone; until then the frame-plus-cloth stand-in
    /// keeps the interaction, positioning and UI exactly as they will be.
    /// The serialised <see cref="ArtifactData"/> is the local fallback; when
    /// an experience payload is active, <see cref="ExperienceContent"/>
    /// merges its artifact over these values by slug. This component never
    /// builds a network request — opening the panel reports the view to the
    /// content hub, and the bootstrap's client does the sending.
    /// </remarks>
    [DisallowMultipleComponent]
    public sealed class ArtifactSpawner : MonoBehaviour
    {
        const string LogPrefix = "[GriotVR] ";

        [Tooltip("Transform of the placeholder marker on the pedestal that hosts the artifact.")]
        [SerializeField] Transform slot;

        [SerializeField] Material clothMaterial;
        [SerializeField] Material frameMaterial;

        [SerializeField] ArtifactData artifactData = new ArtifactData();

        void Start()
        {
            if (artifactData == null || string.IsNullOrEmpty(artifactData.title))
            {
                Debug.LogWarning(LogPrefix + name + " has no artifact data; nothing spawned.");
                return;
            }

            if (slot == null)
            {
                Debug.LogError(LogPrefix + name + " has no slot assigned; artifact not spawned.");
                return;
            }

            var resolved = ResolveData();

            // The indigo marker cube was the placeholder from Milestone 3 —
            // its pedestal is now taken.
            slot.gameObject.SetActive(false);

            var root = BuildVisual(resolved);
            var interactable = root.AddComponent<ArtifactInteractable>();
            var controller = root.AddComponent<ArtifactController>();
            controller.Initialize(resolved);

            // The controller stays in charge of visibility; the interactable
            // only reports intent. Reporting the view goes to the content
            // hub, not to an API client — scene scripts never touch network
            // types (project README).
            interactable.Activated += controller.Show;
            interactable.Activated += () => ExperienceContent.ReportViewed(resolved.artifactId);

            Debug.Log(
                LogPrefix + "Artifact ready: " + resolved.title +
                " (" + resolved.artifactId + ") on " +
                (slot.parent != null ? slot.parent.name : slot.name) + ".");
        }

        /// <summary>
        /// Backend payload data when one is loaded and matches this
        /// artifact's slug; otherwise the serialised local copy. A payload
        /// without a match is a warning, not a failure — the scene still
        /// shows its own sourced text.
        /// </summary>
        ArtifactData ResolveData()
        {
            if (ExperienceContent.Current == null) return artifactData;

            var remote = ExperienceContent.FindArtifact(artifactData.artifactId);
            if (remote == null)
            {
                Debug.LogWarning(
                    LogPrefix + name + ": payload has no artifact '" +
                    artifactData.artifactId + "'; scene data stays in use.");
                return artifactData;
            }

            Debug.Log(
                LogPrefix + "Artifact content for '" + artifactData.artifactId +
                "' taken from the experience payload.");
            return ExperienceContent.ToArtifactData(remote, artifactData);
        }

        /// <summary>
        /// Frame + cloth built from cubes. The root sits on the pedestal
        /// surface (marker centre minus half its height) so the frame base
        /// rests on the top plate — position is derived from the slot, never
        /// hard-coded, so moving the pedestal moves the artifact.
        /// </summary>
        GameObject BuildVisual(ArtifactData resolved)
        {
            var root = new GameObject(resolved.title + " Artifact");
            root.transform.SetParent(slot.parent, false);
            root.transform.localPosition = slot.localPosition + new Vector3(0f, -0.1f, 0f);

            var frame = GameObject.CreatePrimitive(PrimitiveType.Cube);
            frame.name = "Frame";
            frame.transform.SetParent(root.transform, false);
            frame.transform.localPosition = new Vector3(0f, 0.43f, 0f);
            frame.transform.localScale = new Vector3(0.66f, 0.86f, 0.03f);
            ApplyMaterial(frame, frameMaterial);

            var cloth = GameObject.CreatePrimitive(PrimitiveType.Cube);
            cloth.name = "Cloth";
            cloth.transform.SetParent(root.transform, false);
            cloth.transform.localPosition = new Vector3(0f, 0.43f, 0.021f);
            cloth.transform.localScale = new Vector3(0.58f, 0.78f, 0.012f);
            ApplyMaterial(cloth, clothMaterial);

            // The ray needs exactly one collider to hit; primitives come
            // with their own, so the children's colliders are disabled
            // immediately (Destroy alone is deferred to end of frame, which
            // would leave two competing hit targets for one frame) and a
            // single box covering the frame is placed on the root — the one
            // ArtifactInteractable expects.
            DropChildCollider(frame);
            DropChildCollider(cloth);
            var box = root.AddComponent<BoxCollider>();
            box.center = new Vector3(0f, 0.43f, 0.01f);
            box.size = new Vector3(0.66f, 0.86f, 0.06f);

            return root;
        }

        static void DropChildCollider(GameObject child)
        {
            var primitiveCollider = child.GetComponent<Collider>();
            if (primitiveCollider == null) return;
            primitiveCollider.enabled = false;
            Destroy(primitiveCollider);
        }

        static void ApplyMaterial(GameObject target, Material material)
        {
            if (material != null)
            {
                target.GetComponent<Renderer>().sharedMaterial = material;
                return;
            }

            Debug.LogWarning(
                LogPrefix + target.name + " has no material assigned; falling back to a pipeline default.");

            // Last resort so a missing assignment still renders something
            // readable instead of an invisible object.
            var shader = Shader.Find("Standard");
            if (shader == null) shader = Shader.Find("Universal Render Pipeline/Lit");
            if (shader != null)
            {
                target.GetComponent<Renderer>().sharedMaterial = new Material(shader);
            }
        }
    }
}
