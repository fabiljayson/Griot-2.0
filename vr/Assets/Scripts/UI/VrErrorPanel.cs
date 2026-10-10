using UnityEngine;
using UnityEngine.UI;
using UnityEngine.XR.Interaction.Toolkit.UI;

namespace Griot.VR.UI
{
    /// <summary>
    /// The one place a failure becomes visible: launch refused, server
    /// unreachable, unreadable response — the reader ends up here with
    /// copy written for someone wearing a headset, not for a log file.
    /// </summary>
    /// <remarks>
    /// A world-space uGUI panel built at runtime (same construction rules
    /// as <see cref="ArtifactController"/>: no TextMeshPro, no authored
    /// canvas YAML), shown in front of the player — at the environment
    /// spawn when one is loaded, in front of the head when not. Dismissing
    /// it never retries anything; it only clears the view, because the
    /// fallback state (scene-local content) is already usable behind it.
    /// </remarks>
    public static class VrErrorPanel
    {
        static readonly Color BackgroundColour = new Color(30f / 255f, 43f / 255f, 88f / 255f, 0.97f);
        static readonly Color Bronze = new Color(198f / 255f, 139f / 255f, 41f / 255f, 1f);
        static readonly Color Ivory = new Color(0.96f, 0.94f, 0.88f, 1f);

        static GameObject panel;

        /// <summary>True while the panel is on screen.</summary>
        public static bool IsVisible => panel != null && panel.activeSelf;

        /// <summary>Show a failure. Any previously shown panel is replaced.</summary>
        public static void Show(string headline, string message)
        {
            Hide();

            ArtifactController.EnsureEventSystem();

            Vector3 position;
            Quaternion rotation;
            ResolvePlacement(out position, out rotation);

            var go = new GameObject("VR Error Panel", typeof(RectTransform), typeof(Canvas));
            var canvas = go.GetComponent<Canvas>();
            canvas.renderMode = RenderMode.WorldSpace;

            var rect = go.GetComponent<RectTransform>();
            rect.sizeDelta = new Vector2(900f, 560f);
            rect.SetPositionAndRotation(position, rotation);
            go.transform.localScale = Vector3.one * 0.0012f;

            go.AddComponent<GraphicRaycaster>();
            go.AddComponent<TrackedDeviceGraphicRaycaster>();

            var background = new GameObject("Background", typeof(RectTransform), typeof(Image));
            var backgroundRect = background.GetComponent<RectTransform>();
            backgroundRect.SetParent(rect, false);
            Stretch(backgroundRect);
            background.GetComponent<Image>().color = BackgroundColour;

            var title = AddText(rect, "Title", headline, Bronze, 48);
            SetAnchors(title.rectTransform, new Vector2(0.06f, 0.78f), new Vector2(0.94f, 0.94f));
            title.resizeTextForBestFit = true;
            title.resizeTextMinSize = 30;

            var body = AddText(rect, "Message", message, Ivory, 34);
            SetAnchors(body.rectTransform, new Vector2(0.08f, 0.24f), new Vector2(0.92f, 0.74f));
            body.resizeTextForBestFit = true;
            body.resizeTextMinSize = 20;
            body.alignment = TextAnchor.UpperLeft;

            BuildCloseButton(rect);

            panel = go;
            Debug.Log("[GriotVR] Error panel shown: " + headline);
        }

        /// <summary>Dismiss the panel, if any.</summary>
        public static void Hide()
        {
            if (panel == null) return;
            // Not a MonoBehaviour — the static class must qualify Destroy.
            UnityEngine.Object.Destroy(panel);
            panel = null;
        }

        static void BuildCloseButton(RectTransform parent)
        {
            var go = new GameObject("Close Button", typeof(RectTransform), typeof(Image), typeof(Button));
            var rect = go.GetComponent<RectTransform>();
            rect.SetParent(parent, false);
            SetAnchors(rect, new Vector2(0.32f, 0.06f), new Vector2(0.68f, 0.19f));

            var image = go.GetComponent<Image>();
            image.color = Bronze;

            var button = go.GetComponent<Button>();
            button.targetGraphic = image;
            button.navigation = new Navigation { mode = Navigation.Mode.None };
            button.onClick.AddListener(Hide);

            var label = AddText(rect, "Label", "Close", new Color(20f / 255f, 26f / 255f, 50f / 255f, 1f), 36);
            label.resizeTextForBestFit = true;
            label.resizeTextMinSize = 24;
            Stretch(label.rectTransform, 0.05f);
        }

        /// <summary>
        /// Prefer the environment spawn — the panel then stands where the
        /// player will look after placement — and fall back to a fixed
        /// spot in front of the head (or at the origin) for failures that
        /// happen before any environment is loaded.
        /// </summary>
        static void ResolvePlacement(out Vector3 position, out Quaternion rotation)
        {
            var environment = HeritageEnvironment.Active;
            if (environment != null)
            {
                var spawn = environment.PlayerSpawnPosition;
                var forward = environment.PlayerSpawnRotation * Vector3.forward;
                forward.y = 0f;
                if (forward.sqrMagnitude < 0.0001f) forward = Vector3.forward;
                forward.Normalize();

                position = spawn + forward * 3f;
                position.y = spawn.y + 1.5f;
                rotation = Quaternion.LookRotation(forward);
                return;
            }

            var camera = Camera.main;
            if (camera != null)
            {
                position = camera.transform.position + camera.transform.forward * 2.5f;
                var awayFromViewer = position - camera.transform.position;
                awayFromViewer.y = 0f;
                rotation = awayFromViewer.sqrMagnitude > 0.0001f
                    ? Quaternion.LookRotation(awayFromViewer)
                    : camera.transform.rotation;
                return;
            }

            position = new Vector3(0f, 1.5f, 2f);
            rotation = Quaternion.identity;
        }

        static Text AddText(RectTransform parent, string textName, string content, Color colour, int fontSize)
        {
            var go = new GameObject(textName, typeof(RectTransform), typeof(Text));
            var rect = go.GetComponent<RectTransform>();
            rect.SetParent(parent, false);

            var text = go.GetComponent<Text>();
            text.font = ArtifactController.ResolveUiFont();
            text.text = content;
            text.fontSize = fontSize;
            text.color = colour;
            text.alignment = TextAnchor.MiddleCenter;
            text.horizontalOverflow = HorizontalWrapMode.Wrap;
            text.verticalOverflow = VerticalWrapMode.Truncate;
            return text;
        }

        static void SetAnchors(RectTransform rect, Vector2 min, Vector2 max)
        {
            rect.anchorMin = min;
            rect.anchorMax = max;
            rect.offsetMin = Vector2.zero;
            rect.offsetMax = Vector2.zero;
            rect.localScale = Vector3.one;
        }

        static void Stretch(RectTransform rect)
        {
            rect.anchorMin = Vector2.zero;
            rect.anchorMax = Vector2.one;
            rect.offsetMin = Vector2.zero;
            rect.offsetMax = Vector2.zero;
        }

        static void Stretch(RectTransform rect, float inset)
        {
            rect.anchorMin = Vector2.one * inset;
            rect.anchorMax = Vector2.one * (1f - inset);
            rect.offsetMin = Vector2.zero;
            rect.offsetMax = Vector2.zero;
        }

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
        static void ResetStatics()
        {
            panel = null;
        }
    }
}
