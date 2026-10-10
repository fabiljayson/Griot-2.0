using UnityEngine;
using UnityEngine.UI;

namespace Griot.VR.MobileVR
{
    /// <summary>
    /// Double-tap recentering plus the one-time calibration hint that
    /// teaches it: a small world-space card under the gaze that disappears
    /// the first time the reader recenters (§7 of the Mobile VR spec).
    /// </summary>
    /// <remarks>
    /// The hint state is session-only — nothing is persisted, and a fresh
    /// launch shows it again, which is what a shared museum device wants.
    /// The card uses the project's plain uGUI stack (built-in font through
    /// <see cref="ArtifactController.ResolveUiFont"/>, no TextMeshPro) and
    /// never participates in raycasts so it cannot swallow a tap aimed at
    /// something behind it.
    /// </remarks>
    [DisallowMultipleComponent]
    public sealed class MobileVRRecenter : MonoBehaviour
    {
        static readonly Color HintBackground = new Color(30f / 255f, 43f / 255f, 88f / 255f, 0.88f);

        MobileVRRig rig;
        GameObject hint;

        public void Configure(MobileVRRig mobileRig)
        {
            rig = mobileRig;
            ShowCalibrationHint();
        }

        /// <summary>Wired to <see cref="IGriotVRInput.RecenterRequested"/>.</summary>
        public void OnRecenterRequested()
        {
            if (rig != null && rig.HeadTracker != null) rig.HeadTracker.Recenter();

            if (hint != null)
            {
                Destroy(hint);
                hint = null;
            }
        }

        void ShowCalibrationHint()
        {
            if (hint != null || rig == null || rig.HeadRoot == null) return;

            hint = new GameObject("Calibration Hint", typeof(RectTransform));
            hint.transform.SetParent(rig.HeadRoot, false);
            hint.transform.localPosition = new Vector3(0f, -0.35f, 1f);
            hint.transform.localRotation = Quaternion.identity;
            hint.transform.localScale = Vector3.one * 0.0008f;

            var canvas = hint.AddComponent<Canvas>();
            canvas.renderMode = RenderMode.WorldSpace;
            hint.GetComponent<RectTransform>().sizeDelta = new Vector2(760f, 170f);

            var background = new GameObject("Background", typeof(RectTransform));
            background.transform.SetParent(hint.transform, false);
            var backgroundImage = background.AddComponent<Image>();
            backgroundImage.color = HintBackground;
            backgroundImage.raycastTarget = false;
            Stretch(background.GetComponent<RectTransform>());

            var label = new GameObject("Label", typeof(RectTransform));
            label.transform.SetParent(hint.transform, false);
            var text = label.AddComponent<Text>();
            text.font = ArtifactController.ResolveUiFont();
            text.text = "Place your phone straight ahead.\nDouble tap to recenter";
            text.fontSize = 52;
            text.alignment = TextAnchor.MiddleCenter;
            text.color = Color.white;
            text.horizontalOverflow = HorizontalWrapMode.Wrap;
            text.verticalOverflow = VerticalWrapMode.Overflow;
            text.raycastTarget = false;
            Stretch(label.GetComponent<RectTransform>());
        }

        static void Stretch(RectTransform rect)
        {
            rect.anchorMin = Vector2.zero;
            rect.anchorMax = Vector2.one;
            rect.offsetMin = Vector2.zero;
            rect.offsetMax = Vector2.zero;
        }
    }
}
