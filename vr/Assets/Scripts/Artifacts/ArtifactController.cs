using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;
using UnityEngine.XR.Interaction.Toolkit.UI;

namespace Griot.VR
{
    /// <summary>
    /// The content shown for one artifact: an always-visible name plate plus
    /// a world-space information panel with the cultural description, a
    /// Learn More expansion and a Close button.
    /// </summary>
    /// <remarks>
    /// The panel is built at runtime from plain uGUI (Image/Text/Button)
    /// rather than authored scene YAML: TextMeshPro would demand its
    /// essential assets be imported first, and hand-writing a Canvas tree
    /// that has to parse is exactly the risk this project avoids elsewhere.
    /// Data arrives through <see cref="ArtifactData"/> only — no API, no
    /// static caches — so the Django payload merge in
    /// <see cref="ArtifactSpawner"/> swaps the source without touching
    /// this component.
    /// </remarks>
    [DisallowMultipleComponent]
    public sealed class ArtifactController : MonoBehaviour
    {
        const string LogPrefix = "[GriotVR] ";

        // Brand palette (see vr/README.md and frontend AppColors).
        static readonly Color BackgroundColour = new Color(30f / 255f, 43f / 255f, 88f / 255f, 0.97f);
        static readonly Color Bronze = new Color(198f / 255f, 139f / 255f, 41f / 255f, 1f);
        static readonly Color Ivory = new Color(0.96f, 0.94f, 0.88f, 1f);

        ArtifactData data;
        CanvasParts panel;
        Text bodyText;
        Button learnMoreButton;
        Text learnMoreLabel;
        bool showingLearnMore;

        /// <summary>True while the information panel is visible.</summary>
        public bool IsPanelOpen => panel != null && panel.gameObject.activeSelf;

        /// <summary>
        /// Builds the name plate and (hidden) information panel. Call once,
        /// right after the artifact is spawned.
        /// </summary>
        public void Initialize(ArtifactData artifactData)
        {
            data = artifactData;
            if (data == null)
            {
                Debug.LogWarning(LogPrefix + name + " initialized without data; panel disabled.");
                return;
            }

            var facing = ResolveFacingDirection();

            var plate = BuildCanvas("Name Plate", new Vector2(500f, 110f), 0.001f);
            plate.rectTransform.SetParent(transform, false);
            plate.rectTransform.localPosition = new Vector3(0f, 0.98f, 0f);
            plate.rectTransform.rotation = facing;
            var plateBackground = AddBackground(plate.rectTransform);
            plateBackground.color = new Color(BackgroundColour.r, BackgroundColour.g, BackgroundColour.b, 0.9f);
            var plateText = AddText(plate.rectTransform, "Plate Text", data.title, Bronze, 60);
            plateText.resizeTextForBestFit = true;
            plateText.resizeTextMinSize = 30;
            Stretch(plateText.rectTransform, 0.04f);

            panel = BuildCanvas("Information Panel", new Vector2(1000f, 700f), 0.0012f);
            panel.rectTransform.SetParent(transform, false);
            panel.rectTransform.localPosition = new Vector3(0.95f, 0.4f, 0.1f);
            panel.rectTransform.rotation = facing;
            panel.gameObject.SetActive(false);

            var background = AddBackground(panel.rectTransform);
            background.color = BackgroundColour;

            var title = AddText(panel.rectTransform, "Title", data.title, Bronze, 56);
            SetAnchors(title.rectTransform, new Vector2(0.05f, 0.84f), new Vector2(0.95f, 0.96f));
            title.resizeTextForBestFit = true;
            title.resizeTextMinSize = 32;

            bodyText = AddText(panel.rectTransform, "Body", data.description, Ivory, 40);
            SetAnchors(bodyText.rectTransform, new Vector2(0.06f, 0.34f), new Vector2(0.94f, 0.82f));
            bodyText.resizeTextForBestFit = true;
            bodyText.resizeTextMinSize = 22;
            bodyText.alignment = TextAnchor.UpperLeft;

            learnMoreLabel = null;
            learnMoreButton = BuildButton(
                panel.rectTransform, "Learn More Button", "Learn More",
                Bronze, new Color(20f / 255f, 26f / 255f, 50f / 255f, 1f),
                new Vector2(0.06f, 0.05f), new Vector2(0.5f, 0.28f),
                OnLearnMorePressed);
            learnMoreLabel = learnMoreButton.GetComponentInChildren<Text>();

            BuildButton(
                panel.rectTransform, "Close Button", "Close",
                Ivory, new Color(20f / 255f, 26f / 255f, 50f / 255f, 1f),
                new Vector2(0.54f, 0.05f), new Vector2(0.94f, 0.28f),
                Hide);
        }

        /// <summary>Opens the information panel, resetting to the summary.</summary>
        public void Show()
        {
            if (panel == null) return;

            EnsureEventSystem();
            if (showingLearnMore) ResetBody();
            panel.gameObject.SetActive(true);
        }

        /// <summary>Closes the information panel.</summary>
        public void Hide()
        {
            if (panel == null) return;
            panel.gameObject.SetActive(false);
        }

        void OnLearnMorePressed()
        {
            if (showingLearnMore)
            {
                ResetBody();
                return;
            }

            showingLearnMore = true;

            // A payload or scene copy with no significance still deserves a
            // readable panel; and "Source:" is only printed when there is
            // actually a source to print.
            var text = data.historicalSignificance;
            if (string.IsNullOrEmpty(text))
            {
                text = "No additional historical details have been provided for this artifact.";
            }
            if (!string.IsNullOrEmpty(data.sourceLabel))
            {
                text += "\n\nSource: " + data.sourceLabel;
            }

            bodyText.text = text;
            learnMoreLabel.text = "Back";
        }

        void ResetBody()
        {
            showingLearnMore = false;
            bodyText.text = data.description;
            if (learnMoreLabel != null) learnMoreLabel.text = "Learn More";
        }

        /// <summary>
        /// Panel rotation that shows the readable face to the player: uGUI
        /// world-space canvases render on their -Z side, so forward must
        /// point away from the viewer — from the spawn point through the
        /// panel. Falls back to identity (readable from the entrance) when
        /// no environment spawn exists yet.
        /// </summary>
        Quaternion ResolveFacingDirection()
        {
            var environment = HeritageEnvironment.Active;
            if (environment == null) return Quaternion.identity;

            var awayFromViewer = transform.position + Vector3.up * 0.4f
                                 - environment.PlayerSpawnPosition;
            awayFromViewer.y = 0f;
            if (awayFromViewer.sqrMagnitude < 0.0001f) return Quaternion.identity;

            return Quaternion.LookRotation(awayFromViewer);
        }

        // ---- world-space canvas construction --------------------------------

        sealed class CanvasParts
        {
            public GameObject gameObject;
            public RectTransform rectTransform;
        }

        CanvasParts BuildCanvas(string canvasName, Vector2 size, float worldScale)
        {
            var go = new GameObject(canvasName, typeof(RectTransform), typeof(Canvas));
            var canvas = go.GetComponent<Canvas>();
            canvas.renderMode = RenderMode.WorldSpace;

            var rect = go.GetComponent<RectTransform>();
            rect.sizeDelta = size;
            go.transform.localScale = Vector3.one * worldScale;

            // Both raycasters: GraphicRaycaster is the uGUI baseline (and
            // what the Editor uses), TrackedDeviceGraphicRaycaster is what
            // makes the XR ray interact with the canvas (XRI manual, "Set up
            // UI Canvases for XR").
            go.AddComponent<GraphicRaycaster>();
            go.AddComponent<TrackedDeviceGraphicRaycaster>();

            return new CanvasParts { gameObject = go, rectTransform = rect };
        }

        Text AddText(RectTransform parent, string textName, string content, Color colour, int fontSize)
        {
            var go = new GameObject(textName, typeof(RectTransform), typeof(Text));
            var rect = go.GetComponent<RectTransform>();
            rect.SetParent(parent, false);

            var text = go.GetComponent<Text>();
            text.font = ResolveUiFont();
            text.text = content;
            text.fontSize = fontSize;
            text.color = colour;
            text.alignment = TextAnchor.MiddleCenter;
            text.horizontalOverflow = HorizontalWrapMode.Wrap;
            text.verticalOverflow = VerticalWrapMode.Truncate;
            return text;
        }

        /// <summary>
        /// A stretched Image child — the first sibling, so everything else
        /// draws on top. Graphics cannot live on the canvas root itself, so
        /// the backdrop is its own child.
        /// </summary>
        static Image AddBackground(RectTransform parent)
        {
            var go = new GameObject("Background", typeof(RectTransform), typeof(Image));
            var rect = go.GetComponent<RectTransform>();
            rect.SetParent(parent, false);
            Stretch(rect, 0f);
            return go.GetComponent<Image>();
        }

        Button BuildButton(
            RectTransform parent, string buttonName, string label,
            Color faceColour, Color textColour,
            Vector2 anchorMin, Vector2 anchorMax, UnityEngine.Events.UnityAction onClick)
        {
            var go = new GameObject(buttonName, typeof(RectTransform), typeof(Image), typeof(Button));
            var rect = go.GetComponent<RectTransform>();
            rect.SetParent(parent, false);
            SetAnchors(rect, anchorMin, anchorMax);

            var image = go.GetComponent<Image>();
            image.color = faceColour;

            var button = go.GetComponent<Button>();
            button.targetGraphic = image;
            // XR UI navigation is pointer-driven; keyboard/controller
            // navigation states would only add phantom highlights.
            button.navigation = new Navigation { mode = Navigation.Mode.None };
            button.onClick.AddListener(onClick);

            var labelText = AddText(rect, "Label", label, textColour, 40);
            labelText.resizeTextForBestFit = true;
            labelText.resizeTextMinSize = 24;
            Stretch(labelText.rectTransform, 0.05f);
            return button;
        }

        static void SetAnchors(RectTransform rect, Vector2 min, Vector2 max)
        {
            rect.anchorMin = min;
            rect.anchorMax = max;
            rect.offsetMin = Vector2.zero;
            rect.offsetMax = Vector2.zero;
            rect.localScale = Vector3.one;
        }

        static void Stretch(RectTransform rect, float inset)
        {
            rect.anchorMin = Vector2.one * inset;
            rect.anchorMax = Vector2.one * (1f - inset);
            rect.offsetMin = Vector2.zero;
            rect.offsetMax = Vector2.zero;
        }

        /// <summary>
        /// Unity 6 ships "LegacyRuntime.ttf" as the built-in dynamic font
        /// (the old Arial resource was removed in 2022.2). Plain uGUI Text is
        /// used instead of TextMeshPro precisely so no "Import TMP
        /// Essentials" step stands between a fresh clone and readable UI.
        /// Public so <see cref="UI.VrErrorPanel"/> renders with the same font.
        /// </summary>
        static Font uiFont;
        public static Font ResolveUiFont()
        {
            if (uiFont != null) return uiFont;
            uiFont = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
            if (uiFont == null)
            {
                // OS fallback so a missing built-in degrades to readable
                // text instead of invisible glyphs.
                uiFont = Font.CreateDynamicFontFromOSFont("Arial", 40);
            }
            return uiFont;
        }

        // ---- XR event system ------------------------------------------------

        /// <summary>
        /// uGUI buttons only respond when an <see cref="EventSystem"/> with
        /// an <see cref="XRUIInputModule"/> exists. The rig prefab may or may
        /// not ship one, so the first panel open guarantees it — and
        /// disables any legacy input module that would throw every frame
        /// under the Input System package. Public because the error panel
        /// needs the same guarantee before its first button press.
        /// </summary>
        public static void EnsureEventSystem()
        {
            var eventSystem = FindAnyObjectByType<EventSystem>();
            if (eventSystem == null)
            {
                var go = new GameObject("XR Event System");
                go.AddComponent<EventSystem>();
                go.AddComponent<XRUIInputModule>();
                return;
            }

            if (eventSystem.GetComponent<XRUIInputModule>() == null)
            {
                eventSystem.gameObject.AddComponent<XRUIInputModule>();
            }

            foreach (var module in eventSystem.GetComponents<BaseInputModule>())
            {
                if (module is XRUIInputModule) continue;
                Debug.Log(
                    LogPrefix + "Disabling legacy input module " + module.GetType().Name +
                    " on the EventSystem (Input System package is active).");
                module.enabled = false;
            }
        }
    }

    /// <summary>
    /// Content for one artifact. Field names mirror the Django
    /// <c>qr_codes.Artifact</c> model (culture, region, materials,
    /// source_url) so the local serialised data can be replaced by an API
    /// payload field-for-field in Milestone 5 without renaming anything.
    /// </summary>
    /// <remarks>
    /// This milestone ships local, sourced text only — the Ndop copy below
    /// lives in the scene's <c>ArtifactSpawner</c> with its provenance, and
    /// nothing in this class knows what a network is.
    /// </remarks>
    [System.Serializable]
    public sealed class ArtifactData
    {
        public string artifactId;
        public string title;

        [TextArea(3, 6)] public string description;
        [TextArea(6, 10)] public string historicalSignificance;

        public string culture;
        public string region;
        public string materials;

        public string sourceLabel;
        public string sourceUrl;
    }
}
