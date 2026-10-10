using UnityEngine;
using UnityEngine.XR.Interaction.Toolkit;

namespace Griot.VR
{
    /// <summary>
    /// Guarantees an XR Interaction Manager exists before any interactor or
    /// interactable enables, and keeps it alive across scene loads.
    /// </summary>
    /// <remarks>
    /// Lives on the bootstrap object, which <see cref="GriotVrBootstrap"/>
    /// marks DontDestroyOnLoad — the manager therefore precedes both the rig's
    /// interactors (Bootstrap scene) and later scenes' interactables (Museum).
    /// The execution order of -200 is what makes "precedes" a guarantee rather
    /// than a coincidence: Unity runs lower orders first, and XRI interactors
    /// look for the manager during their own OnEnable. Creating the manager in
    /// code (instead of scene YAML) again avoids hand-authored package script
    /// GUIDs; see <see cref="GriotInteractable"/> for that rationale.
    /// </remarks>
    [DefaultExecutionOrder(-200)]
    [DisallowMultipleComponent]
    public sealed class VRInteractionManager : MonoBehaviour
    {
        const string LogPrefix = "[GriotVR] ";

        XRInteractionManager xriManager;

        /// <summary>The underlying XRI manager component.</summary>
        public XRInteractionManager Xri => xriManager;

        void Awake()
        {
            xriManager = FindAnyObjectByType<XRInteractionManager>(FindObjectsInactive.Include);
            if (xriManager != null) return;

            // Added to this (persistent) GameObject so it survives the
            // single-scene loads that follow the bootstrap.
            xriManager = gameObject.AddComponent<XRInteractionManager>();
            Debug.Log(LogPrefix + "XR Interaction Manager created on " + gameObject.name + ".");
        }
    }
}
