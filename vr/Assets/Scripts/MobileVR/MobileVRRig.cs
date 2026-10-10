using Unity.XR.CoreUtils;
using UnityEngine;

namespace Griot.VR.MobileVR
{
    /// <summary>
    /// The phone VR rig, built entirely in code: a root at standing
    /// position, a head pivot carrying the gyroscope rotation, two half-screen
    /// eye cameras, the gaze stack and the tap input. Created once by
    /// <see cref="MobileVRRuntime"/> and kept across scene loads.
    /// </summary>
    /// <remarks>
    /// <para>
    /// Nothing XR: no <c>XROrigin</c>, no tracked pose, no loader — the
    /// spec's hard requirement that a phone build never initialises XR
    /// (§4). If the Bootstrap scene does contain an <see cref="XROrigin"/>
    /// (the Editor setup tool creates one for the headset path), it is
    /// switched off here — its camera would otherwise render over the eyes
    /// and its audio listener would double up.
    /// </para>
    /// <para>
    /// Procedural construction also means zero scene YAML edits for this
    /// feature: the Bootstrap scene keeps the two runtimes' shared
    /// components only, and both rigs appear at boot.
    /// </para>
    /// </remarks>
    [DisallowMultipleComponent]
    public sealed class MobileVRRig : MonoBehaviour
    {
        [Header("Eye comfort")]
        [SerializeField, Range(0.5f, 2.2f)] float eyeHeight = 1.6f;
        [SerializeField, Range(0.04f, 0.09f)] float eyeSeparation = 0.064f;
        [SerializeField] float nearClipPlane = 0.05f;
        [SerializeField] float farClipPlane = 150f;
        [SerializeField, Range(45f, 90f)] float fieldOfView = 60f;

        public static MobileVRRig Current { get; private set; }

        public Transform HeadRoot { get; private set; }
        public MobileVRStereoCamera LeftEye { get; private set; }
        public MobileVRStereoCamera RightEye { get; private set; }
        public MobileVRHeadTracker HeadTracker { get; private set; }
        public MobileVRInput Input { get; private set; }
        public MobileVRRecenter Recenter { get; private set; }
        public MobileVRGazeInteractor Gaze { get; private set; }
        public MobileVRReticle Reticle { get; private set; }

        public float EyeSeparation => eyeSeparation;

        public static MobileVRRig Create()
        {
            DisableConflictingXrOrigin();

            var go = new GameObject("Mobile VR Rig");
            var rig = go.AddComponent<MobileVRRig>();
            rig.Build();

            DontDestroyOnLoad(go);
            Current = rig;
            return rig;
        }

        void Build()
        {
            var head = new GameObject("Head");
            head.transform.SetParent(transform, false);
            head.transform.localPosition = new Vector3(0f, eyeHeight, 0f);
            HeadRoot = head.transform;

            LeftEye = MobileVRStereoCamera.Create(HeadRoot, "Left Eye", true, nearClipPlane, farClipPlane, fieldOfView);
            RightEye = MobileVRStereoCamera.Create(HeadRoot, "Right Eye", false, nearClipPlane, farClipPlane, fieldOfView);
            LeftEye.transform.localPosition = new Vector3(-eyeSeparation * 0.5f, 0f, 0f);
            RightEye.transform.localPosition = new Vector3(eyeSeparation * 0.5f, 0f, 0f);

            HeadTracker = head.AddComponent<MobileVRHeadTracker>();
            HeadTracker.Configure(this);

            Input = gameObject.AddComponent<MobileVRInput>();
            Input.Configure(this);

            Recenter = gameObject.AddComponent<MobileVRRecenter>();
            Recenter.Configure(this);

            Reticle = MobileVRReticle.Create(HeadRoot);

            Gaze = gameObject.AddComponent<MobileVRGazeInteractor>();
            Gaze.Configure(this, Reticle);
            Gaze.enabled = false; // waits for the environment (§23: reticle appears with the museum)

            Input.SelectPressed += Gaze.OnSelectPressed;
            Input.RecenterRequested += Recenter.OnRecenterRequested;

            Debug.Log(
                "[GriotVR] Mobile VR rig built: eye height " + eyeHeight.ToString("0.00") +
                " m, IPD " + eyeSeparation.ToString("0.000") +
                " m, FOV " + fieldOfView.ToString("0") + "°.");
        }

        /// <summary>
        /// Called when the environment is ready: the reticle becomes the
        /// idle ring and gaze input starts steering it.
        /// </summary>
        public void ShowReticle()
        {
            if (Gaze != null) Gaze.enabled = true;
            Reticle?.SetState(MobileVRReticleState.Idle);
        }

        /// <summary>
        /// Instant locomotion step (§9): moves the whole rig — head and eyes
        /// are children, so tracking and comfort math stay untouched — and
        /// optionally snap-rotates to the marker's facing.
        /// </summary>
        public void TeleportTo(Vector3 position, Quaternion? facing)
        {
            transform.position = position;
            if (facing.HasValue) transform.rotation = facing.Value;
        }

        static void DisableConflictingXrOrigin()
        {
            var origin = FindAnyObjectByType<XROrigin>(FindObjectsInactive.Include);
            if (origin == null || !origin.gameObject.activeInHierarchy) return;

            origin.gameObject.SetActive(false);
            Debug.Log(
                "[GriotVR] Disabled the scene XR Origin for the mobile runtime; " +
                "its cameras and XR components would fight the phone rig.");
        }

        void OnDestroy()
        {
            if (Current == this) Current = null;
        }
    }
}
