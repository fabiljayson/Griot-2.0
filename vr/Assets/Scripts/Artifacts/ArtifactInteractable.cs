using System;
using UnityEngine;
using UnityEngine.XR.Interaction.Toolkit;
using UnityEngine.XR.Interaction.Toolkit.Interactables;

namespace Griot.VR
{
    /// <summary>
    /// Turns an artifact object into a point-and-select target: adds an XRI
    /// <c>XRSimpleInteractable</c> at runtime, tints it bronze while the ray
    /// is on it, and raises <see cref="Activated"/> when the trigger is
    /// pressed.
    /// </summary>
    /// <remarks>
    /// Deliberately not an <c>XRGrabInteractable</c> (unlike
    /// <see cref="GriotInteractable"/>): a museum piece stays on its
    /// pedestal — the interaction is "look and select", not "pick up". The
    /// XRI component is added at runtime for the same reason as elsewhere in
    /// this project: package script GUIDs cannot be authored reliably by
    /// hand, so the scene YAML stays ours. The XR Interaction Manager must
    /// exist first — <see cref="VRInteractionManager"/> guarantees that with
    /// an execution order of -200.
    /// </remarks>
    [DisallowMultipleComponent]
    public sealed class ArtifactInteractable : MonoBehaviour
    {
        static readonly int BaseColorProperty = Shader.PropertyToID("_BaseColor");
        static readonly int ColorProperty = Shader.PropertyToID("_Color");

        const string LogPrefix = "[GriotVR] ";

        XRSimpleInteractable interactable;
        Renderer viewRenderer;
        MaterialPropertyBlock tintBlock;
        int tintPropertyId;
        bool hasTintProperty;
        Color restingTint;

        /// <summary>Raised once per trigger press / controller select.</summary>
        public event Action Activated;

        /// <summary>True while any interactor's ray is on this artifact.</summary>
        public bool IsTargeted => interactable != null && interactable.isHovered;

        void Awake()
        {
            // The interaction needs a collider to hit; a missing one is a
            // setup mistake, but a generated BoxCollider keeps the artifact
            // usable when the visual is built at runtime.
            if (!TryGetComponent<Collider>(out _))
            {
                var box = gameObject.AddComponent<BoxCollider>();
                box.center = new Vector3(0f, 0.43f, 0.01f);
                box.size = new Vector3(0.66f, 0.86f, 0.06f);
            }

            interactable = GetComponent<XRSimpleInteractable>();
            if (interactable == null)
            {
                interactable = gameObject.AddComponent<XRSimpleInteractable>();
            }

            interactable.hoverEntered.AddListener(OnHoverEntered);
            interactable.hoverExited.AddListener(OnHoverExited);
            interactable.selectEntered.AddListener(OnSelectEntered);

            ResolveViewRenderer();
        }

        void OnDestroy()
        {
            if (interactable == null) return;

            interactable.hoverEntered.RemoveListener(OnHoverEntered);
            interactable.hoverExited.RemoveListener(OnHoverExited);
            interactable.selectEntered.RemoveListener(OnSelectEntered);
        }

        void OnHoverEntered(HoverEnterEventArgs args)
        {
            SetTint(GriotInteractable.SelectedTint);
        }

        void OnHoverExited(HoverExitEventArgs args)
        {
            SetTint(restingTint);
        }

        void OnSelectEntered(SelectEnterEventArgs args)
        {
            Activated?.Invoke();
        }

        /// <summary>
        /// The renderer may sit on this object or on a visual child; either
        /// way the highlight is a MaterialPropertyBlock so no material
        /// instances are created (and none can leak). Mirrors the approach in
        /// <see cref="GriotInteractable"/> — the two components tint
        /// different interaction states (hover vs grab) but never touch each
        /// other's objects.
        /// </summary>
        void ResolveViewRenderer()
        {
            viewRenderer = GetComponent<Renderer>();
            if (viewRenderer == null) viewRenderer = GetComponentInChildren<Renderer>(true);
            if (viewRenderer == null)
            {
                Debug.LogWarning(LogPrefix + name + " has no Renderer; hover highlight disabled.");
                return;
            }

            var sharedMaterial = viewRenderer.sharedMaterial;
            if (sharedMaterial == null) return;

            // URP Lit exposes _BaseColor, Built-in Standard exposes _Color;
            // probe instead of assuming a render pipeline.
            if (sharedMaterial.HasProperty(BaseColorProperty))
                tintPropertyId = BaseColorProperty;
            else if (sharedMaterial.HasProperty(ColorProperty))
                tintPropertyId = ColorProperty;
            else
            {
                Debug.LogWarning(LogPrefix + name + " material has no colour property; hover highlight disabled.");
                return;
            }

            hasTintProperty = true;
            tintBlock = new MaterialPropertyBlock();
            restingTint = sharedMaterial.GetColor(tintPropertyId);
        }

        void SetTint(Color tint)
        {
            if (!hasTintProperty || viewRenderer == null) return;

            viewRenderer.GetPropertyBlock(tintBlock);
            tintBlock.SetColor(tintPropertyId, tint);
            viewRenderer.SetPropertyBlock(tintBlock);
        }
    }
}
