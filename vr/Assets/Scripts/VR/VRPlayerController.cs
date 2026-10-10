using System;
using Unity.XR.CoreUtils;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.XR;
// Input System and XR both define CommonUsages; this component only ever
// means the XR feature usages (tracking state, hand nodes).
using CommonUsages = UnityEngine.XR.CommonUsages;

namespace Griot.VR
{
    /// <summary>
    /// Runtime view of the player's rig: head, hands and the two trigger
    /// buttons that count as basic Griot VR input.
    /// </summary>
    /// <remarks>
    /// Hand references are resolved by name because XR Origin rigs differ
    /// between XRI versions and sample imports; a missing hand is a warning,
    /// never a crash. Locomotion, teleport and snap turning are provided by
    /// the XRI rig itself (the Starter Assets "XR Origin (XR Rig)" prefab,
    /// installed by Tools > Griot > Setup Locomotion and Interaction) — this
    /// component deliberately moves nothing. The trigger actions below only
    /// observe state for Griot logic; XRI reads the same controls through its
    /// own actions, which the Input System allows in parallel.
    /// </remarks>
    [DisallowMultipleComponent]
    public sealed class VRPlayerController : MonoBehaviour
    {
        const string LogPrefix = "[GriotVR] ";

        [SerializeField] XROrigin origin;
        [SerializeField] Transform head;
        [SerializeField] Transform leftHand;
        [SerializeField] Transform rightHand;

#if ENABLE_INPUT_SYSTEM
        InputAction leftTrigger;
        InputAction rightTrigger;
#endif

        /// <summary>Raised on press and release. handIndex: 0 = left, 1 = right.</summary>
        public event Action<int, bool> TriggerChanged;

        public XROrigin Origin => origin;
        public Transform Head => head;
        public Transform LeftHand => leftHand;
        public Transform RightHand => rightHand;

        /// <summary>True when the headset reports position and rotation.</summary>
        public bool IsHeadTracked
        {
            get
            {
                var device = InputDevices.GetDeviceAtXRNode(XRNode.Head);
                if (!device.isValid) return false;

                InputTrackingState state;
                return device.TryGetFeatureValue(CommonUsages.trackingState, out state)
                       && (state & (InputTrackingState.Position | InputTrackingState.Rotation)) != 0;
            }
        }

        void Awake()
        {
            ResolveRig();
            CreateTriggerActions();
        }

        void OnDestroy()
        {
#if ENABLE_INPUT_SYSTEM
            if (leftTrigger != null)
            {
                leftTrigger.Disable();
                leftTrigger = null;
            }
            if (rightTrigger != null)
            {
                rightTrigger.Disable();
                rightTrigger = null;
            }
#endif
        }

        void ResolveRig()
        {
            if (origin == null) origin = FindAnyObjectByType<XROrigin>();
            if (origin == null)
            {
                Debug.LogError(LogPrefix + "VRPlayerController could not find an XR Origin.");
                return;
            }

            if (head == null)
            {
                var headCamera = origin.Camera != null ? origin.Camera : GetComponentInChildren<Camera>(true);
                head = headCamera != null ? headCamera.transform : null;
                if (head == null)
                    Debug.LogWarning(LogPrefix + "No head camera found on the XR Origin.");
            }

            if (leftHand == null) leftHand = FindHand("left");
            if (rightHand == null) rightHand = FindHand("right");

            if (leftHand == null || rightHand == null)
                Debug.LogWarning(
                    LogPrefix + "Controller transforms not found on the rig; " +
                    "run 'Tools > Griot > Setup Locomotion and Interaction' to " +
                    "install the full XR rig.");
        }

        /// <summary>
        /// Rig children are named differently across XRI versions
        /// ("Left Controller", "LeftHand Controller", …), so match on the two
        /// words that are always present.
        /// </summary>
        Transform FindHand(string side)
        {
            var candidates = origin.GetComponentsInChildren<Transform>(true);
            foreach (var candidate in candidates)
            {
                var name = candidate.name;
                if (name.IndexOf(side, StringComparison.OrdinalIgnoreCase) >= 0
                    && name.IndexOf("controller", StringComparison.OrdinalIgnoreCase) >= 0)
                {
                    return candidate;
                }
            }

            return null;
        }

        void CreateTriggerActions()
        {
#if ENABLE_INPUT_SYSTEM
            leftTrigger = new InputAction(
                "GriotLeftTrigger", InputActionType.Button, "<XRController>{LeftHand}/trigger");
            rightTrigger = new InputAction(
                "GriotRightTrigger", InputActionType.Button, "<XRController>{RightHand}/trigger");

            leftTrigger.started += _ => TriggerChanged?.Invoke(0, true);
            leftTrigger.canceled += _ => TriggerChanged?.Invoke(0, false);
            rightTrigger.started += _ => TriggerChanged?.Invoke(1, true);
            rightTrigger.canceled += _ => TriggerChanged?.Invoke(1, false);

            leftTrigger.Enable();
            rightTrigger.Enable();
#else
            Debug.LogWarning(
                LogPrefix + "Input System is not the active input handler; trigger " +
                "input is disabled. Set Active Input Handling to 'Input System " +
                "Package (New)' in Project Settings > Player and restart the Editor.");
#endif
        }
    }
}
