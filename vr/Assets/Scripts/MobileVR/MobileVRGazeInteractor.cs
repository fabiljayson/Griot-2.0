using System.Collections.Generic;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.XR.Interaction.Toolkit;
using UnityEngine.XR.Interaction.Toolkit.Interactables;
using UnityEngine.XR.Interaction.Toolkit.Interactors;

namespace Griot.VR.MobileVR
{
    /// <summary>
    /// The reader's eye: every frame it raycasts from the head, decides what
    /// the gaze rests on (navigation marker, artifact, then UI), steers the
    /// reticle, and turns the tap gesture into the right activation —
    /// teleport, panel open, or button click.
    /// </summary>
    /// <remarks>
    /// <para>
    /// Artifacts are reached through a tiny <see cref="GazeAdapter"/> that
    /// poses as an <c>XRBaseInteractor</c> to the existing
    /// <see cref="VRInteractionManager"/>: its <c>GetValidTargets</c> returns
    /// whatever the physics ray hit, so XRI itself drives hover enter/exit
    /// (the bronze tint in <see cref="ArtifactInteractable"/> fires with zero
    /// changes there) and a tap performs a manual selection (the
    /// <c>Activated</c> event that opens the panel fires the same way it does
    /// for a controller ray). §11 of the Mobile VR spec — adapters, no
    /// rewrites of the artifact system.
    /// </para>
    /// <para>
    /// World-space UI (artifact panels, error panel) is reached without XRI:
    /// a plain <c>EventSystem.RaycastAll</c> at the gaze point, then
    /// <c>ExecuteEvents</c> dispatch — the path <c>GraphicRaycaster</c>
    /// supports natively through the left eye's <c>MainCamera</c> tag.
    /// Priority is marker → UI → artifact: an open panel visually occludes
    /// the room, so a button wins over whatever stands behind it. The
    /// EventSystem's input modules are disabled in mobile mode so this
    /// dispatch is the only click driver — a screen tap elsewhere can never
    /// double-fire the gazed button.
    /// </para>
    /// </remarks>
    [DisallowMultipleComponent]
    public sealed class MobileVRGazeInteractor : MonoBehaviour
    {
        const float MaxGazeDistance = 25f;
        const float DefaultReticleDistance = 1.5f;
        const float ReticleSurfaceOffset = 0.02f;
        const float SelectedFlashSeconds = 0.3f;

        MobileVRRig rig;
        GazeAdapter adapter;
        Transform head;
        MobileVRReticle reticle;

        MobileVRNavigationPoint markerTarget;
        IXRSelectInteractable artifactTarget;
        GameObject uiTarget;
        float markerDistance = DefaultReticleDistance;
        float artifactDistance = DefaultReticleDistance;

        float selectedUntil = float.NegativeInfinity;
        PointerEventData uiPointer;
        readonly List<RaycastResult> uiHits = new List<RaycastResult>(8);

        public void Configure(MobileVRRig mobileRig, MobileVRReticle gazeReticle)
        {
            rig = mobileRig;
            reticle = gazeReticle;
            head = mobileRig.HeadRoot;

            // The adapter rides the head root: XRI asks it for targets every
            // frame (XRInteractionManager.GetValidTargets loop), and this is
            // the transform manual selection attaches to.
            adapter = head.gameObject.AddComponent<GazeAdapter>();

            EnsureQuietEventSystem();
            uiPointer = new PointerEventData(EventSystem.current);
        }

        /// <summary>
        /// EventSystem with every input module disabled: mobile input is
        /// owned by <see cref="MobileVRInput"/> + this class, and leaving
        /// <c>XRUIInputModule</c> active would let it process raw touches
        /// into a second, competing set of pointer events.
        /// </summary>
        static void EnsureQuietEventSystem()
        {
            ArtifactController.EnsureEventSystem();
            var eventSystem = EventSystem.current;
            if (eventSystem == null) return;

            foreach (var module in eventSystem.GetComponents<BaseInputModule>())
                module.enabled = false;
        }

        void Update()
        {
            if (rig == null || head == null) return;

            var ray = new Ray(head.position, head.forward);

            MobileVRNavigationPoint newMarker = null;
            IXRSelectInteractable newArtifact = null;
            var newMarkerDistance = DefaultReticleDistance;
            var newArtifactDistance = DefaultReticleDistance;

            if (Physics.Raycast(ray, out var hit, MaxGazeDistance, ~0, QueryTriggerInteraction.Collide))
            {
                var marker = hit.collider.GetComponentInParent<MobileVRNavigationPoint>();
                if (marker != null)
                {
                    newMarker = marker;
                    newMarkerDistance = hit.distance;
                }
                else
                {
                    var simple = hit.collider.GetComponentInParent<XRSimpleInteractable>();
                    if (simple != null)
                    {
                        newArtifact = simple;
                        newArtifactDistance = hit.distance;
                    }
                }
            }

            var roomTargetPresent = newMarker != null || newArtifact != null;

            // UI only when the room is not under the gaze: an open panel is
            // drawn in front of everything behind it.
            GameObject newUi = null;
            if (!roomTargetPresent && EventSystem.current != null)
                newUi = RaycastUi();

            UpdateMarkerHover(newMarker);
            UpdateUiHover(newUi);

            // The adapter's target swap is all XRI needs — it diffs and
            // raises hoverEntered/hoverExited itself, frame by frame.
            markerTarget = newMarker;
            artifactTarget = newArtifact;
            markerDistance = newMarkerDistance;
            artifactDistance = newArtifactDistance;
            uiTarget = newUi;
            adapter.SetTarget(newArtifact);

            UpdateReticle();
        }

        GameObject RaycastUi()
        {
            uiPointer.position = rig.LeftEye != null && rig.LeftEye.Eye != null
                ? rig.LeftEye.Eye.ViewportToScreenPoint(new Vector3(0.5f, 0.5f))
                : new Vector3(Screen.width * 0.25f, Screen.height * 0.5f);

            uiHits.Clear();
            EventSystem.current.RaycastAll(uiPointer, uiHits);
            return uiHits.Count > 0 ? uiHits[0].gameObject : null;
        }

        /// <summary>
        /// Where the reticle sits while UI is hovered: the intersection of
        /// the gaze ray with the hit panel's own plane, so the ring lands
        /// on the button it is highlighting instead of behind the canvas
        /// (which would hide it under depth test). <c>RaycastResult</c>
        /// carries no world position from <c>GraphicRaycaster</c>, hence the
        /// explicit line–plane solve; orientation-agnostic by construction.
        /// </summary>
        float UiDistance()
        {
            var rect = uiTarget.GetComponentInParent<RectTransform>();
            if (rect == null) return DefaultReticleDistance;

            var ray = new Ray(head.position, head.forward);
            var normal = rect.forward;
            var denominator = Vector3.Dot(normal, ray.direction);
            if (Mathf.Abs(denominator) < 1e-4f) return DefaultReticleDistance;

            var enter = Vector3.Dot(normal, rect.position - ray.origin) / denominator;
            return enter >= 0f
                ? Mathf.Clamp(enter, 0.3f, MaxGazeDistance)
                : DefaultReticleDistance;
        }

        void UpdateMarkerHover(MobileVRNavigationPoint next)
        {
            if (markerTarget == next) return;
            if (markerTarget != null) markerTarget.SetGazeHovered(false);
            if (next != null) next.SetGazeHovered(true);
        }

        void UpdateUiHover(GameObject next)
        {
            if (uiTarget == next) return;
            if (uiTarget != null) ExecuteEvents.Execute(uiTarget, uiPointer, ExecuteEvents.pointerExitHandler);
            if (next != null) ExecuteEvents.Execute(next, uiPointer, ExecuteEvents.pointerEnterHandler);
        }

        void UpdateReticle()
        {
            if (reticle == null) return;

            float distance;
            MobileVRReticleState state;

            if (markerTarget != null)
            {
                distance = markerDistance;
                state = MobileVRReticleState.Hover;
            }
            else if (uiTarget != null)
            {
                distance = UiDistance();
                state = MobileVRReticleState.Hover;
            }
            else if (artifactTarget != null)
            {
                distance = artifactDistance;
                state = MobileVRReticleState.Hover;
            }
            else
            {
                distance = DefaultReticleDistance;
                state = MobileVRReticleState.Idle;
            }

            if (Time.unscaledTime < selectedUntil) state = MobileVRReticleState.Selected;

            reticle.SetState(state);
            reticle.SetDistance(Mathf.Max(distance - ReticleSurfaceOffset, 0.3f));
        }

        /// <summary>
        /// The tap: teleport, open, or click — whichever target the gaze is
        /// resting on. Called by the rig when <see cref="IGriotVRInput.SelectPressed"/>
        /// fires (one gesture, three possible meanings, never two at once).
        /// </summary>
        public void OnSelectPressed()
        {
            selectedUntil = Time.unscaledTime + SelectedFlashSeconds;

            if (markerTarget != null)
            {
                markerTarget.Teleport(rig);
                return;
            }

            if (uiTarget != null)
            {
                ClickUi();
                return;
            }

            if (artifactTarget != null)
            {
                // SelectEnter → ArtifactInteractable.OnSelectEntered →
                // Activated → ArtifactController.Show (same chain as a
                // controller trigger; nothing artifact-side knows about us).
                adapter.StartManualInteraction(artifactTarget);
                adapter.EndManualInteraction();
            }
        }

        void ClickUi()
        {
            var handler = ExecuteEvents.GetEventHandler<IPointerClickHandler>(uiTarget);
            if (handler == null) return;

            uiPointer.button = PointerEventData.InputButton.Left;
            ExecuteEvents.Execute(handler, uiPointer, ExecuteEvents.pointerDownHandler);
            ExecuteEvents.Execute(handler, uiPointer, ExecuteEvents.pointerUpHandler);
            ExecuteEvents.Execute(handler, uiPointer, ExecuteEvents.pointerClickHandler);
        }

        /// <summary>
        /// XRI's per-frame target query, replaced by "whatever the gaze is
        /// on". Registered with the existing manager on enable like every
        /// other interactor — the manager drives hover enter/exit from this
        /// list without knowing it is not a real ray.
        /// </summary>
        sealed class GazeAdapter : XRBaseInteractor
        {
            IXRInteractable current;

            public void SetTarget(IXRInteractable next) => current = next;

            public override void GetValidTargets(List<IXRInteractable> targets)
            {
                targets.Clear();
                if (current != null) targets.Add(current);
            }
        }
    }
}
