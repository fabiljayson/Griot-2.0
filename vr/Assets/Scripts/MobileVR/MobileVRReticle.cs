using UnityEngine;

namespace Griot.VR.MobileVR
{
    /// <summary>What the gaze reticle is telling the reader right now.</summary>
    public enum MobileVRReticleState
    {
        /// <summary>Not yet shown (boot / before the environment).</summary>
        Hidden,

        /// <summary>Looking at nothing — indigo, resting size.</summary>
        Idle,

        /// <summary>Looking at an artifact, marker or button — bronze, larger.</summary>
        Hover,

        /// <summary>Just selected — bronze flash at the largest size.</summary>
        Selected,
    }

    /// <summary>
    /// The ring that shows where the reader is looking: an annulus mesh
    /// built in code, parented to the rig's head root, sitting either on
    /// the physics/UI hit or at a fixed comfortable distance in free air.
    /// </summary>
    /// <remarks>
    /// §24 of the Mobile VR spec: colour is never the only signal — each
    /// state also changes size (1.0 / 1.25 / 1.5), so the state survives
    /// colour-blind readers and the dim indigo-on-indigo contrast worst
    /// case. The shader probe mirrors <see cref="ArtifactInteractable"/>:
    /// URP Unlit when a scriptable pipeline is active, the built-in Unlit
    /// otherwise, so the reticle renders on either pipeline without an
    /// authored material (which would need a GUID we cannot hand-author).
    /// </remarks>
    [DisallowMultipleComponent]
    public sealed class MobileVRReticle : MonoBehaviour
    {
        public static readonly Color IdleColour = new Color(30f / 255f, 43f / 255f, 88f / 255f, 1f);   // Griot Indigo #1E2B58
        public static readonly Color HoverColour = new Color(198f / 255f, 139f / 255f, 41f / 255f, 1f); // Griot Bronze #C68B29

        static readonly int BaseColorProperty = Shader.PropertyToID("_BaseColor");
        static readonly int ColorProperty = Shader.PropertyToID("_Color");

        const int Segments = 32;

        Renderer view;
        Material material;
        int tintPropertyId;
        bool hasTintProperty;
        MobileVRReticleState state = MobileVRReticleState.Hidden;

        public static MobileVRReticle Create(Transform headRoot)
        {
            var go = new GameObject("Gaze Reticle");
            go.transform.SetParent(headRoot, false);
            go.transform.localPosition = new Vector3(0f, 0f, 1.5f);

            var filter = go.AddComponent<MeshFilter>();
            filter.sharedMesh = BuildRingMesh();

            var renderer = go.AddComponent<MeshRenderer>();
            renderer.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            renderer.receiveShadows = false;
            renderer.sharedMaterial = BuildMaterial();

            var reticle = go.AddComponent<MobileVRReticle>();
            reticle.view = renderer;
            reticle.material = renderer.sharedMaterial;
            renderer.enabled = false; // SetState(Hidden) below is a no-op on first call

            if (reticle.material != null)
            {
                if (reticle.material.HasProperty(BaseColorProperty))
                {
                    reticle.tintPropertyId = BaseColorProperty;
                    reticle.hasTintProperty = true;
                }
                else if (reticle.material.HasProperty(ColorProperty))
                {
                    reticle.tintPropertyId = ColorProperty;
                    reticle.hasTintProperty = true;
                }
            }

            reticle.SetState(MobileVRReticleState.Hidden);
            return reticle;
        }

        public void SetState(MobileVRReticleState next)
        {
            if (state == next) return;
            state = next;

            switch (next)
            {
                case MobileVRReticleState.Hidden:
                    view.enabled = false;
                    break;
                case MobileVRReticleState.Idle:
                    Apply(IdleColour, 1f);
                    break;
                case MobileVRReticleState.Hover:
                    Apply(HoverColour, 1.25f);
                    break;
                case MobileVRReticleState.Selected:
                    Apply(HoverColour, 1.5f);
                    break;
            }
        }

        /// <summary>Distance from the eyes: onto the hit (pulled 2 cm toward
        /// the viewer to avoid z-fighting the surface), or the rest position.</summary>
        public void SetDistance(float distance)
        {
            transform.localPosition = new Vector3(0f, 0f, distance);
        }

        void Apply(Color colour, float scale)
        {
            view.enabled = true;
            transform.localScale = new Vector3(scale, scale, scale);
            if (!hasTintProperty) return;
            material.SetColor(tintPropertyId, colour);
        }

        /// <summary>
        /// Flat annulus, no gradient: winding chosen so the face normal is
        /// −Z, i.e. toward the camera on both eyes (both cameras share the
        /// head's rotation, so one winding serves both).
        /// </summary>
        static Mesh BuildRingMesh()
        {
            const float outerRadius = 0.06f;
            const float innerRadius = 0.045f;

            var vertices = new Vector3[Segments * 2];
            var normals = new Vector3[Segments * 2];
            var triangles = new int[Segments * 6];

            for (var i = 0; i < Segments; i++)
            {
                var angle = i * Mathf.PI * 2f / Segments;
                var cos = Mathf.Cos(angle);
                var sin = Mathf.Sin(angle);
                vertices[i] = new Vector3(cos * outerRadius, sin * outerRadius, 0f);
                vertices[i + Segments] = new Vector3(cos * innerRadius, sin * innerRadius, 0f);
                normals[i] = Vector3.back;
                normals[i + Segments] = Vector3.back;
            }

            for (var i = 0; i < Segments; i++)
            {
                var outer = i;
                var inner = (i + Segments);
                var outerNext = (i + 1) % Segments;
                var innerNext = (i + 1) % Segments + Segments;

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
                name = "Gaze Reticle Ring",
                vertices = vertices,
                normals = normals,
                triangles = triangles,
            };
            mesh.RecalculateBounds();
            return mesh;
        }

        static Material BuildMaterial()
        {
            var pipelineActive = UnityEngine.Rendering.GraphicsSettings.currentRenderPipeline != null;
            var shader =
                (pipelineActive ? Shader.Find("Universal Render Pipeline/Unlit") : null) ??
                Shader.Find("Unlit/Color") ??
                Shader.Find("Unlit/Transparent") ??
                Shader.Find("Sprites/Default");

            if (shader == null)
            {
                Debug.LogWarning("[GriotVR] No unlit shader found for the gaze reticle; it will not render.");
                return null;
            }

            return new Material(shader);
        }
    }
}
