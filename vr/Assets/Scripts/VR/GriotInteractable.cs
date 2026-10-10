using System;
using UnityEngine;
using UnityEngine.XR;
using UnityEngine.XR.Interaction.Toolkit;
using UnityEngine.XR.Interaction.Toolkit.Interactables;

namespace Griot.VR
{
    /// <summary>
    /// Turns a plain scene object into a grabbable one: adds the XRI
    /// components at runtime, tints the object while it is held, and pulses
    /// the controller that grabbed it.
    /// </summary>
    /// <remarks>
    /// The XRI pieces are added at runtime instead of being serialised into
    /// the scene because package script GUIDs cannot be authored reliably by
    /// hand; a self-configuring component keeps the scene YAML ours only. The
    /// XR Interaction Manager must exist before the grab component enables —
    /// <see cref="VRInteractionManager"/> guarantees that with an execution
    /// order of -200.
    /// </remarks>
    [DisallowMultipleComponent]
    public sealed class GriotInteractable : MonoBehaviour
    {
        static readonly int BaseColorProperty = Shader.PropertyToID("_BaseColor");
        static readonly int ColorProperty = Shader.PropertyToID("_Color");

        /// <summary>Griot brand bronze (#C68B29) — the selection tint.</summary>
        public static readonly Color SelectedTint =
            new Color(198f / 255f, 139f / 255f, 41f / 255f, 1f);

        const string LogPrefix = "[GriotVR] ";

        XRGrabInteractable grab;
        Renderer viewRenderer;
        MaterialPropertyBlock tintBlock;
        int tintPropertyId;
        bool hasTintProperty;
        Color restingTint;

        /// <summary>True while any interactor is holding this object.</summary>
        public bool IsGrabbed => grab != null && grab.isSelected;

        void Awake()
        {
            // Added explicitly as well as through XRGrabInteractable's
            // RequireComponent, so behaviour does not depend on whether the
            // engine enforces RequireComponent for runtime AddComponent.
            if (!TryGetComponent<Rigidbody>(out _))
            {
                gameObject.AddComponent<Rigidbody>();
            }

            grab = GetComponent<XRGrabInteractable>();
            if (grab == null)
            {
                grab = gameObject.AddComponent<XRGrabInteractable>();
            }

            grab.selectEntered.AddListener(OnSelectEntered);
            grab.selectExited.AddListener(OnSelectExited);

            ResolveViewRenderer();
        }

        void OnDestroy()
        {
            if (grab == null) return;

            grab.selectEntered.RemoveListener(OnSelectEntered);
            grab.selectExited.RemoveListener(OnSelectExited);
        }

        void OnSelectEntered(SelectEnterEventArgs args)
        {
            SetTint(SelectedTint);
            PulseHaptic(args.interactorObject as Component);
        }

        void OnSelectExited(SelectExitEventArgs args)
        {
            SetTint(restingTint);
        }

        /// <summary>
        /// The renderer may sit on this object or on a model child; either
        /// way the highlight is a MaterialPropertyBlock so no material
        /// instances are created (and none can leak).
        /// </summary>
        void ResolveViewRenderer()
        {
            viewRenderer = GetComponent<Renderer>();
            if (viewRenderer == null) viewRenderer = GetComponentInChildren<Renderer>(true);
            if (viewRenderer == null)
            {
                Debug.LogWarning(LogPrefix + name + " has no Renderer; selection highlight disabled.");
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
                Debug.LogWarning(LogPrefix + name + " material has no colour property; selection highlight disabled.");
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

        /// <summary>
        /// Short amplitude pulse on the controller that initiated the grab.
        /// The device is found by walking up from the interactor, because the
        /// XRI event exposes an interface, not a controller component. Devices
        /// that do not support haptics (hand tracking, the simulator) are a
        /// silent no-op.
        /// </summary>
        static void PulseHaptic(Component interactor)
        {
            var node = ResolveControllerNode(interactor != null ? interactor.transform : null);
            if (node == null) return;

            var device = InputDevices.GetDeviceAtXRNode(node.Value);
            if (device.isValid)
            {
                device.SendHapticImpulse(0, 0.7f, 0.15f);
            }
        }

        /// <summary>
        /// The controller node the grab came from, or null when the walk up
        /// the hierarchy finds no hand/controller name — XRNode has no
        /// "none" member, so absence is expressed with the nullable type.
        /// </summary>
        static XRNode? ResolveControllerNode(Transform start)
        {
            const int MaxDepth = 8;
            var current = start;
            for (var depth = 0; current != null && depth < MaxDepth; depth++, current = current.parent)
            {
                var name = current.name;
                var isLeft = name.IndexOf("left", StringComparison.OrdinalIgnoreCase) >= 0;
                var isRight = name.IndexOf("right", StringComparison.OrdinalIgnoreCase) >= 0;
                if (!isLeft && !isRight) continue;

                var looksLikeHand = name.IndexOf("controller", StringComparison.OrdinalIgnoreCase) >= 0
                                    || name.IndexOf("hand", StringComparison.OrdinalIgnoreCase) >= 0;
                if (!looksLikeHand) continue;

                return isLeft ? XRNode.LeftHand : XRNode.RightHand;
            }

            return null;
        }
    }
}
