using System;
using UnityEngine;

namespace Griot.VR
{
    /// <summary>
    /// <see cref="IGriotVRInput"/> for the headset path: either XR trigger
    /// becomes <see cref="SelectPressed"/>.
    /// </summary>
    /// <remarks>
    /// Purely an observer. XRI keeps reading the same controls through its
    /// own action assets — this class never moves anything and never changes
    /// how the existing rig interacts; it only surfaces the shared gesture
    /// events for code that must work on both platforms.
    /// </remarks>
    public sealed class HeadsetVRInput : IGriotVRInput
    {
        VRPlayerController controller;

        public event Action SelectPressed;

        /// <summary>
        /// Never raised on the headset: recentering there belongs to the
        /// XR runtime. Empty accessors keep the interface honest without a
        /// CS0067 "never used" warning.
        /// </summary>
        public event Action RecenterRequested
        {
            add { }
            remove { }
        }

        public bool IsAvailable => FindController() != null;

        public HeadsetVRInput()
        {
            var found = FindController();
            if (found != null) Subscribe(found);
        }

        VRPlayerController FindController()
        {
            if (controller != null) return controller;
            controller = UnityEngine.Object.FindAnyObjectByType<VRPlayerController>();
            return controller;
        }

        void Subscribe(VRPlayerController target)
        {
            target.TriggerChanged += OnTriggerChanged;
        }

        void OnTriggerChanged(int handIndex, bool pressed)
        {
            if (pressed) SelectPressed?.Invoke();
        }
    }
}
