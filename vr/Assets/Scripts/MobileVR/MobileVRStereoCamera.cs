using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Griot.VR.MobileVR
{
    /// <summary>
    /// One eye of the side-by-side stereo pair: a plain camera whose
    /// viewport is squeezed into half the screen and which is deliberately
    /// not an XR tracked camera.
    /// </summary>
    /// <remarks>
    /// <para>
    /// No <c>TrackedPoseDriver</c>, no <c>XRNode.Head</c> — head motion
    /// comes from <see cref="MobileVRHeadTracker"/> writing the parent's
    /// local rotation, which is what keeps the phone path free of any XR
    /// subsystem (§4 of the Mobile VR spec).
    /// </para>
    /// <para>
    /// The left eye carries the <c>MainCamera</c> tag because
    /// <c>GraphicRaycaster.eventCamera</c> falls back to
    /// <see cref="Camera.main"/>: that single tag is what lets the existing
    /// world-space UI panels raycast correctly on the phone without touching
    /// <see cref="ArtifactController"/>. The viewport honours
    /// <see cref="Screen.safeArea"/> so notched screens do not spill one eye
    /// into the other.
    /// </para>
    /// </remarks>
    [DisallowMultipleComponent]
    public sealed class MobileVRStereoCamera : MonoBehaviour
    {
        Camera eye;
        float viewportOriginX;
        bool leftEye;
        int lastScreenWidth = -1;
        int lastScreenHeight = -1;

        public Camera Eye => eye;

        public static MobileVRStereoCamera Create(
            Transform parent,
            string cameraName,
            bool isLeftEye,
            float near,
            float far,
            float fov)
        {
            var go = new GameObject(cameraName);
            go.transform.SetParent(parent, false);
            if (isLeftEye) go.tag = "MainCamera";

            var camera = go.AddComponent<Camera>();
            camera.clearFlags = CameraClearFlags.Skybox;
            camera.nearClipPlane = near;
            camera.farClipPlane = far;
            camera.fieldOfView = fov;
            camera.depth = isLeftEye ? 0f : 1f;
            camera.stereoTargetEye = StereoTargetEyeMask.None;
            camera.allowHDR = false;

            if (isLeftEye) go.AddComponent<AudioListener>();

            // Built-in pipeline renders as-is; URP needs its per-camera
            // data component or the camera skips rendering entirely.
            if (GraphicsSettings.currentRenderPipeline != null)
                camera.GetUniversalAdditionalCameraData();

            var stereo = go.AddComponent<MobileVRStereoCamera>();
            stereo.eye = camera;
            stereo.leftEye = isLeftEye;
            stereo.viewportOriginX = isLeftEye ? 0f : 0.5f;
            stereo.ApplyViewport();
            return stereo;
        }

        void Update()
        {
            if (Screen.width == lastScreenWidth && Screen.height == lastScreenHeight) return;
            ApplyViewport();
        }

        void ApplyViewport()
        {
            lastScreenWidth = Screen.width;
            lastScreenHeight = Screen.height;
            if (lastScreenWidth <= 0 || lastScreenHeight <= 0) return;

            var safe = Screen.safeArea;
            var fullWidth = safe.width / lastScreenWidth;
            var halfWidth = fullWidth * 0.5f;

            eye.rect = new Rect(
                safe.x / lastScreenWidth + viewportOriginX * halfWidth,
                safe.y / lastScreenHeight,
                halfWidth,
                safe.height / lastScreenHeight);
        }
    }
}
