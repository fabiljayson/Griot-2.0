using System.Collections.Generic;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.XR.Interaction.Toolkit;
using UnityEngine.XR.Interaction.Toolkit.Locomotion.Teleportation;
using Unity.XR.CoreUtils;

namespace Griot.VR.EditorTools
{
    /// <summary>
    /// Installs and configures the movement side of Milestone 2: the XRI
    /// Starter Assets sample, the fully configured "XR Origin (XR Rig)"
    /// prefab (teleport, snap turning, optional smooth locomotion, ray and
    /// direct interactors), and the Griot glue components on the rig.
    /// </summary>
    /// <remarks>
    /// The prefab is used instead of assembling locomotion by hand because
    /// XRI 3.0 expects a specific provider graph (Locomotion Mediator plus
    /// providers on the rig) that the sample prefab ships correctly wired.
    /// Everything here degrades to a report line rather than an exception, so
    /// a missing sample or a moved menu path never blocks the rest of setup.
    /// </remarks>
    public static class GriotVrLocomotionSetup
    {
        const string BootstrapScenePath = "Assets/Scenes/Bootstrap.unity";
        const string RigPrefabName = "XR Origin (XR Rig)";
        const string SampleFolderName = "Starter Assets";
        const string SampleRoot = "Assets/Samples/XR Interaction Toolkit";

        [MenuItem("Tools/Griot/Setup Locomotion and Interaction")]
        public static void SetupMenuItem()
        {
            var report = new List<string>();
            Configure(report, true);
            Debug.Log("[GriotVR] Locomotion setup finished:\n - " + string.Join("\n - ", report));
        }

        /// <param name="report">Lines describing what happened and what needs a manual step.</param>
        /// <param name="openBootstrapScene">
        /// True for the bootstrap flow (opens and saves Bootstrap); false for
        /// the menu item that adjusts whichever scene is already open.
        /// </param>
        public static void Configure(List<string> report, bool openBootstrapScene)
        {
            if (openBootstrapScene)
            {
                if (File.Exists(BootstrapScenePath))
                {
                    EditorSceneManager.OpenScene(BootstrapScenePath, OpenSceneMode.Single);
                }
                else
                {
                    report.Add("Bootstrap scene missing at " + BootstrapScenePath + " — rig goes into the open scene instead.");
                }
            }

            var rigPrefab = EnsureRigPrefab(report);
            EnsureRig(rigPrefab, report);
            SaveActiveScene(report);
        }

        /// <summary>
        /// Returns the Starter Assets rig prefab, importing the XRI sample
        /// into the project if it is not there yet.
        /// </summary>
        static GameObject EnsureRigPrefab(List<string> report)
        {
            var existing = FindRigPrefab();
            if (existing != null)
            {
                report.Add("Starter Assets sample: already imported (" + AssetDatabase.GetAssetPath(existing) + ").");
                return existing;
            }

            var packageInfo = UnityEditor.PackageManager.PackageInfo.FindForAssembly(
                typeof(XRInteractionManager).Assembly);
            if (packageInfo == null || string.IsNullOrEmpty(packageInfo.resolvedPath))
            {
                report.Add(
                    "XR Interaction Toolkit package not resolved — import the sample " +
                    "manually (Window > Package Manager > XR Interaction Toolkit > " +
                    "Samples > Starter Assets > Import), then re-run.");
                return null;
            }

            var source = Path.Combine(packageInfo.resolvedPath, "Samples~", SampleFolderName)
                .Replace('\\', '/');
            if (!Directory.Exists(source))
            {
                report.Add(
                    "Sample source missing at " + source + " — import Starter Assets " +
                    "from the Package Manager, then re-run.");
                return null;
            }

            var destination = SampleRoot + "/" + packageInfo.version + "/" + SampleFolderName;
            if (Directory.Exists(destination))
            {
                // A partial copy from an earlier attempt: refresh instead of
                // copying over it, which would nest the folder one level deep.
                AssetDatabase.Refresh(ImportAssetOptions.ForceSynchronousImport);
                var recovered = FindRigPrefab();
                if (recovered != null)
                {
                    report.Add("Starter Assets sample: already imported (" + AssetDatabase.GetAssetPath(recovered) + ").");
                    return recovered;
                }

                report.Add(
                    "Partial sample at " + destination + " — delete that folder and " +
                    "re-run, or import the sample from the Package Manager.");
                return null;
            }

            Directory.CreateDirectory(destination);
            FileUtil.CopyFileOrDirectory(source, destination);
            AssetDatabase.Refresh(ImportAssetOptions.ForceSynchronousImport);

            report.Add("Starter Assets sample imported to " + destination + ".");
            report.Add(
                "Known XRI issue: if the Console shows 'Could not parse input action in " +
                "JSON format', select 'XRI Default Input Actions' > Inspector > Generate " +
                "C# Class > Apply, then delete the generated class.");
            report.Add(
                "If sample materials render magenta, install Shader Graph (Window > " +
                "Package Manager > Shader Graph > Install).");

            var imported = FindRigPrefab();
            if (imported == null)
            {
                report.Add("Rig prefab still not found after import — check the Console for import errors.");
            }

            return imported;
        }

        static GameObject FindRigPrefab()
        {
            GameObject fallback = null;
            foreach (var guid in AssetDatabase.FindAssets(RigPrefabName + " t:Prefab"))
            {
                var path = AssetDatabase.GUIDToAssetPath(guid);
                if (Path.GetFileNameWithoutExtension(path) != RigPrefabName) continue;

                var prefab = AssetDatabase.LoadAssetAtPath<GameObject>(path);
                if (prefab == null) continue;

                if (path.Contains(SampleFolderName)) return prefab;
                fallback = fallback ?? prefab;
            }

            return fallback;
        }

        static void EnsureRig(GameObject rigPrefab, List<string> report)
        {
            var origin = Object.FindAnyObjectByType<XROrigin>();

            if (origin != null && !HasLocomotion(origin))
            {
                if (rigPrefab != null)
                {
                    // A rig from the GameObject menu has no provider graph;
                    // keeping it would silently disable teleport and turning.
                    report.Add("XR Origin: bare rig (no locomotion) found — replacing with the Starter Assets rig.");
                    Undo.DestroyObjectImmediate(origin.gameObject);
                    origin = null;
                }
                else
                {
                    report.Add("XR Origin: bare rig found but the sample is not imported — re-run after importing.");
                }
            }

            if (origin == null)
            {
                if (rigPrefab == null)
                {
                    if (!TryCreateMenuRig(report)) return;
                    origin = Object.FindAnyObjectByType<XROrigin>();
                    if (origin == null) return;
                }
                else
                {
                    var instance = (GameObject)PrefabUtility.InstantiatePrefab(rigPrefab);
                    Undo.RegisterCreatedObjectUndo(instance, "Create XR Rig");
                    instance.transform.SetPositionAndRotation(Vector3.zero, Quaternion.identity);
                    origin = instance.GetComponent<XROrigin>();
                    report.Add(
                        "XR Origin (XR Rig) instantiated — teleport, snap turn, smooth " +
                        "move and ray/direct/poke interactors per hand are pre-wired.");
                }
            }
            else
            {
                report.Add("XR Origin: Starter Assets rig already in the scene.");
            }

            if (origin == null) return;

            EnsureComponent<VRPlayerController>(origin.gameObject, report);
            EnsureComponent<VRTeleportController>(origin.gameObject, report);
            report.Add(
                "Interaction manager: VRInteractionManager on the bootstrap object " +
                "creates the XR Interaction Manager at runtime.");
        }

        /// <summary>
        /// The provider graph lives on the rig; a teleportation provider
        /// somewhere underneath the origin is the marker that this is the
        /// configured prefab and not a bare menu rig.
        /// </summary>
        static bool HasLocomotion(XROrigin origin)
        {
            return origin.GetComponentInChildren<TeleportationProvider>(true) != null;
        }

        static bool TryCreateMenuRig(List<string> report)
        {
            // Fallback path kept from Milestone 1 so a missing sample still
            // yields a head-tracked rig; the report says what is missing.
            string[] menuPaths =
            {
                "GameObject/XR/XR Origin (VR)",
                "GameObject/XR/XR Origin (XR)",
                "GameObject/XR/XR Origin",
            };

            var created = menuPaths.Any(EditorApplication.ExecuteMenuItem);
            if (created && Object.FindAnyObjectByType<XROrigin>() != null)
            {
                report.Add(
                    "XR Origin created via the GameObject menu (bare rig — no teleport " +
                    "or turning; import the Starter Assets sample and re-run).");
                return true;
            }

            report.Add(
                "XR Origin could not be created — open the Bootstrap scene and use " +
                "GameObject > XR > XR Origin (VR), then re-run.");
            return false;
        }

        static void EnsureComponent<T>(GameObject target, List<string> report)
            where T : Component
        {
            var label = typeof(T).Name;
            if (target.GetComponent<T>() != null)
            {
                report.Add(label + ": already attached to the rig.");
                return;
            }

            Undo.AddComponent<T>(target);
            report.Add(label + ": attached to the rig.");
        }

        static void SaveActiveScene(List<string> report)
        {
            var scene = UnityEngine.SceneManagement.SceneManager.GetActiveScene();
            if (!scene.IsValid() || string.IsNullOrEmpty(scene.path)) return;

            if (EditorSceneManager.SaveScene(scene))
                report.Add("Saved " + scene.path + ".");
        }
    }
}
