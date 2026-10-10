using System;
using UnityEngine;
using UnityEngine.InputSystem;

namespace Griot.VR.MobileVR
{
    /// <summary>
    /// The phone's two gestures: a tap is "select what I am looking at", a
    /// double tap recenters the view (§7 of the Mobile VR spec).
    /// </summary>
    /// <remarks>
    /// <para>
    /// Delays a single tap by <see cref="DoubleTapWindow"/> seconds so the
    /// second tap of a double tap can cancel it — the alternative (fire
    /// immediately, undo on the second tap) would open and close a panel
    /// inside 300 ms, which reads as a glitch. Holding or dragging is not a
    /// tap: that is how the Editor's mouse-drag look keeps from selecting
    /// every time the look gesture ends.
    /// </para>
    /// <para>
    /// Input Actions are created in code with an explicit touch and mouse
    /// binding — no .inputactions asset, no GUIDs authored by hand, and the
    /// same code path drives the Editor simulation and the device.
    /// </para>
    /// </remarks>
    [DisallowMultipleComponent]
    public sealed class MobileVRInput : MonoBehaviour, IGriotVRInput
    {
        const float DoubleTapWindow = 0.3f;
        const float MaxTapDuration = 0.4f;
        const float MaxTapDriftPixels = 20f;

        public event Action SelectPressed;
        public event Action RecenterRequested;

        public bool IsAvailable => true;

        InputAction press;
        InputAction pressPosition;

        float pressStartTime;
        Vector2 pressStartPosition;
        bool pressActive;

        float lastTapTime = float.NegativeInfinity;
        float pendingSelectAt = -1f;

        MobileVRRig rig;

        public void Configure(MobileVRRig mobileRig)
        {
            rig = mobileRig;
        }

        void Awake()
        {
            press = new InputAction("Mobile Tap", InputActionType.Button);
            press.AddBinding("<Touchscreen>/primaryTouch/press");
            press.AddBinding("<Mouse>/leftButton");

            pressPosition = new InputAction("Mobile Pointer", InputActionType.Value);
            pressPosition.AddBinding("<Pointer>/position");

            press.started += OnPressStarted;
            press.canceled += OnPressCanceled;
            press.Enable();
            pressPosition.Enable();
        }

        void OnDestroy()
        {
            if (press == null) return;
            press.started -= OnPressStarted;
            press.canceled -= OnPressCanceled;
            press.Disable();
            pressPosition.Disable();
            press.Dispose();
            pressPosition.Dispose();
        }

        void OnPressStarted(InputAction.CallbackContext _)
        {
            pressActive = true;
            pressStartTime = Time.unscaledTime;
            pressStartPosition = pressPosition.ReadValue<Vector2>();
        }

        void OnPressCanceled(InputAction.CallbackContext _)
        {
            if (!pressActive) return;
            pressActive = false;

            var duration = Time.unscaledTime - pressStartTime;
            var drift = pressPosition.ReadValue<Vector2>() - pressStartPosition;
            if (duration > MaxTapDuration || drift.sqrMagnitude > MaxTapDriftPixels * MaxTapDriftPixels)
                return; // a hold or a drag-look, not a tap

            HandleTap();
        }

        void HandleTap()
        {
            var now = Time.unscaledTime;
            if (now - lastTapTime <= DoubleTapWindow)
            {
                // Second tap: this is a recenter, and the select the first
                // tap was waiting for must never fire.
                lastTapTime = float.NegativeInfinity;
                pendingSelectAt = -1f;
                RecenterRequested?.Invoke();
                return;
            }

            lastTapTime = now;
            pendingSelectAt = now + DoubleTapWindow;
        }

        void Update()
        {
            if (pendingSelectAt > 0f && Time.unscaledTime >= pendingSelectAt)
            {
                pendingSelectAt = -1f;
                SelectPressed?.Invoke();
            }

            if (Application.isEditor) EditorWASD();
        }

        /// <summary>
        /// Editor-only rig movement (§32): WASD walks the rig root so the
        /// whole museum is reachable without a teleport test scene. Never
        /// compiled onto a device — the phone moves only by teleport.
        /// </summary>
        void EditorWASD()
        {
            var keyboard = Keyboard.current;
            if (keyboard == null || rig == null) return;

            var delta = Vector3.zero;
            if (keyboard.wKey.isPressed) delta += rig.transform.forward;
            if (keyboard.sKey.isPressed) delta -= rig.transform.forward;
            if (keyboard.aKey.isPressed) delta -= rig.transform.right;
            if (keyboard.dKey.isPressed) delta += rig.transform.right;
            if (delta.sqrMagnitude <= 0f) return;

            delta.y = 0f;
            rig.transform.position += delta.normalized * (2.5f * Time.unscaledDeltaTime);
        }
    }
}
