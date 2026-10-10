using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;

namespace Griot.VR.EditorTools
{
    /// <summary>
    /// One menu item that takes a fresh clone to a project that can build for
    /// Quest: editor settings, Android player settings, build scenes, the XR
    /// loader, OpenXR features and the locomotion rig in the Bootstrap scene.
    /// </summary>
    /// <remarks>
    /// Every API that exists only in a package (XR Management, OpenXR) is
    /// reached through reflection on purpose: this file must compile — and be
    /// readable as a checklist — even when a package is missing or a version
    /// moved a method. Anything that cannot be automated is reported with the
    /// exact panel to open, never silently skipped.
    /// </remarks>
    public static class GriotVrProjectSetup
    {
        static readonly string[] RequiredScenes =
        {
            "Assets/Scenes/Bootstrap.unity",
            "Assets/Scenes/Loading.unity",
            "Assets/Scenes/CameroonHeritageMuseum.unity",
            "Assets/Scenes/Museum.unity",
        };

        const string AndroidPackageName = "org.africanteller.griotvr";
        const string OpenXrLoaderType = "UnityEngine.XR.OpenXR.OpenXRPackage";

        [MenuItem("Tools/Griot/Setup VR Project")]
        public static void SetupVrProject()
        {
            var report = new List<string>();

            ConfigureEditorSettings(report);
            ConfigureAndroidPlayerSettings(report);
            ConfigureInputHandler(report);
            ConfigureBuildSettings(report);
            ConfigureMaterialShaders(report);
            ConfigureXrLoader(report);
            EnableOpenXrFeatures(report);
            GriotVrLocomotionSetup.Configure(report, true);

            Debug.Log("[GriotVR] Setup finished:\n - " + string.Join("\n - ", report));
        }

        [MenuItem("Tools/Griot/Add XR Origin To Open Scene")]
        public static void AddXrOriginToOpenScene()
        {
            var report = new List<string>();
            GriotVrLocomotionSetup.Configure(report, false);
            Debug.Log("[GriotVR] XR Origin step:\n - " + string.Join("\n - ", report));
        }

        static void ConfigureEditorSettings(List<string> report)
        {
            EditorSettings.serializationMode = SerializationMode.ForceText;
            EditorSettings.externalVersionControl = "Visible Meta Files";
            report.Add("Asset serialization: Force Text, Visible Meta Files.");
        }

        static void ConfigureAndroidPlayerSettings(List<string> report)
        {
            PlayerSettings.companyName = "African Tellers";
            PlayerSettings.productName = "GriotVR";
            PlayerSettings.bundleVersion = "1.1.0";
            PlayerSettings.colorSpace = ColorSpace.Linear;
            PlayerSettings.defaultInterfaceOrientation = UIOrientation.LandscapeLeft;

            PlayerSettings.SetApplicationIdentifier(BuildTargetGroup.Android, AndroidPackageName);
            PlayerSettings.SetScriptingBackend(BuildTargetGroup.Android, ScriptingImplementation.IL2CPP);
            PlayerSettings.Android.targetArchitectures = AndroidArchitecture.ARM64;
            PlayerSettings.Android.minSdkVersion = AndroidSdkVersions.AndroidApiLevel29;
            PlayerSettings.SetGraphicsAPIs(
                BuildTarget.Android,
                new[] { GraphicsDeviceType.Vulkan, GraphicsDeviceType.OpenGLES3 });

            report.Add(
                "Android player: " + AndroidPackageName + ", IL2CPP, ARM64, API 29+, " +
                "Linear colour space, Vulkan/GLES3.");
        }

        /// <summary>
        /// XRI needs the Input System package active, and the mobile VR
        /// head tracker reads <c>Input.gyro</c> from the legacy interface —
        /// "Both" (2) is the only value that satisfies the two runtimes.
        /// The property is internal, hence the reflection.
        /// </summary>
        static void ConfigureInputHandler(List<string> report)
        {
            const BindingFlags flags = BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic;
            const int bothInputHandlers = 2;

            var property = typeof(PlayerSettings).GetProperty("activeInputHandler", flags);
            if (property != null && property.CanWrite)
            {
                var value = property.PropertyType == typeof(int)
                    ? (object)bothInputHandlers
                    : Enum.ToObject(property.PropertyType, bothInputHandlers);

                if (!Equals(property.GetValue(null), value))
                {
                    property.SetValue(null, value);
                    report.Add(
                        "Active Input Handling: set to Both (Input System + legacy) — restart " +
                        "the Editor if Unity does not reload by itself.");
                }
                else
                {
                    report.Add("Active Input Handling: already Both.");
                }

                return;
            }

            var field = typeof(PlayerSettings).GetField("activeInputHandler", flags);
            if (field != null)
            {
                field.SetValue(null, bothInputHandlers);
                report.Add("Active Input Handling: set to Both — restart the Editor.");
                return;
            }

            report.Add(
                "Active Input Handling: NOT SET — open Project Settings > Player > " +
                "Other Settings and choose 'Both'.");
        }

        static void ConfigureBuildSettings(List<string> report)
        {
            var scenes = RequiredScenes
                .Select(path => new EditorBuildSettingsScene(path, File.Exists(path)))
                .ToArray();

            EditorBuildSettings.scenes = scenes;

            var missing = scenes.Where(scene => !scene.enabled).Select(scene => scene.path).ToArray();
            report.Add(missing.Length == 0
                ? "Build settings: Bootstrap, Loading, CameroonHeritageMuseum, Museum (index order)."
                : "Build settings: missing scene files: " + string.Join(", ", missing));
        }

        /// <summary>
        /// Points every project material at the shader that matches the
        /// active render pipeline. The museum materials serialize both
        /// Standard and URP property names, so the swap keeps their colours
        /// without a manual re-authoring pass.
        /// </summary>
        /// <remarks>
        /// GraphicsSettings regenerates without an SRP asset on a fresh
        /// clone, so built-in (Standard) is the likely first-run answer while
        /// an URP project resolves to Lit. When someone later assigns a URP
        /// asset this step flips on the next setup run — hence the report
        /// line mentions re-running.
        /// </remarks>
        static void ConfigureMaterialShaders(List<string> report)
        {
            var pipeline = GraphicsSettings.currentRenderPipeline;
            var useUrp = pipeline != null;
            var target = Shader.Find(useUrp ? "Universal Render Pipeline/Lit" : "Standard");

            if (target == null)
            {
                report.Add(
                    "Materials: " + (useUrp ? "URP/Lit" : "Standard") + " shader not found — " +
                    "assign shaders manually in Assets/Materials.");
                return;
            }

            if (!AssetDatabase.IsValidFolder("Assets/Materials"))
            {
                report.Add("Materials: Assets/Materials folder missing — skipped.");
                return;
            }

            var swapped = 0;
            foreach (var guid in AssetDatabase.FindAssets("t:Material", new[] { "Assets/Materials" }))
            {
                var path = AssetDatabase.GUIDToAssetPath(guid);
                var material = AssetDatabase.LoadAssetAtPath<Material>(path);
                if (material == null || material.shader == target) continue;

                // Read through the current shader's property names first:
                // HasProperty answers against the active shader, so a
                // Standard material never sees _BaseColor and vice versa.
                var color = material.HasProperty("_BaseColor")
                    ? material.GetColor("_BaseColor")
                    : material.HasProperty("_Color")
                        ? material.GetColor("_Color")
                        : Color.white;
                var smoothness = material.HasProperty("_Smoothness")
                    ? material.GetFloat("_Smoothness")
                    : material.HasProperty("_Glossiness")
                        ? material.GetFloat("_Glossiness")
                        : 0.5f;
                var metallic = material.HasProperty("_Metallic")
                    ? material.GetFloat("_Metallic")
                    : 0f;

                material.shader = target;

                if (material.HasProperty("_BaseColor")) material.SetColor("_BaseColor", color);
                if (material.HasProperty("_Color")) material.SetColor("_Color", color);
                if (material.HasProperty("_Smoothness")) material.SetFloat("_Smoothness", smoothness);
                if (material.HasProperty("_Glossiness")) material.SetFloat("_Glossiness", smoothness);
                if (material.HasProperty("_Metallic")) material.SetFloat("_Metallic", metallic);

                EditorUtility.SetDirty(material);
                swapped++;
            }

            if (swapped > 0) AssetDatabase.SaveAssets();

            report.Add(swapped > 0
                ? "Materials: " + swapped + " set to " + target.name +
                  " (" + (useUrp ? "URP" : "built-in") + " pipeline detected). " +
                  "Re-run setup after changing the render pipeline."
                : "Materials: shaders already match the active pipeline (" +
                  (useUrp ? "URP" : "built-in") + ").");
        }

        static void ConfigureXrLoader(List<string> report)
        {
            const BindingFlags staticFlags = BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic;

            var generalType = FindType("UnityEngine.XR.Management.XRGeneralSettings");
            var perTargetType = FindType("UnityEditor.XR.Management.XRGeneralSettingsPerBuildTarget");
            var metadataType = FindType("UnityEditor.XR.Management.Metadata.XRPackageMetadataStore");

            if (generalType == null || perTargetType == null || metadataType == null)
            {
                report.Add(
                    "XR Management not found — open Project Settings > XR Plug-in " +
                    "Management, enable OpenXR for Android.");
                return;
            }

            var keyField = generalType.GetField("k_SettingsKey", staticFlags);
            if (keyField == null)
            {
                report.Add(
                    "XR Management settings key not found — enable OpenXR for Android " +
                    "in Project Settings > XR Plug-in Management.");
                return;
            }

            var key = keyField.GetValue(null) as string;
            object perTarget = TryGetConfigObject(perTargetType, key);
            if (perTarget == null)
            {
                report.Add(
                    "XR Plug-in Management has not been initialised — open Project " +
                    "Settings > XR Plug-in Management once, enable OpenXR for Android, " +
                    "then re-run this setup.");
                return;
            }

            var getSettings = FindMethod(perTargetType, "SettingsForBuildTarget", 1)
                              ?? FindMethod(perTargetType, "GetSettingsForBuildTarget", 1);
            var androidSettings = InvokeSafe(getSettings, perTarget, new object[] { BuildTargetGroup.Android });

            if (androidSettings == null)
            {
                report.Add(
                    "No Android XR settings yet — open Project Settings > XR Plug-in " +
                    "Management > Android, enable OpenXR, then re-run this setup.");
                return;
            }

            var managerProperty = androidSettings.GetType().GetProperty("Manager", BindingFlags.Public | BindingFlags.Instance);
            var manager = managerProperty != null ? managerProperty.GetValue(androidSettings) : null;
            if (manager == null)
            {
                report.Add(
                    "XR Manager missing — open Project Settings > XR Plug-in " +
                    "Management > Android once, then re-run this setup.");
                return;
            }

            var assignLoader = FindMethod(metadataType, "AssignLoader", 3);
            var assigned = InvokeSafe(
                assignLoader,
                null,
                new object[] { manager, OpenXrLoaderType, BuildTargetGroup.Android });

            report.Add(assigned is bool ok && ok
                ? "OpenXR loader: assigned for Android."
                : "OpenXR loader: NOT ASSIGNED — enable it in Project Settings > " +
                  "XR Plug-in Management > Android.");
        }

        /// <summary>
        /// Turns on Meta Quest Support and the Oculus Touch interaction profile
        /// by matching feature type names, so a renamed class degrades to a
        /// manual instruction instead of a compile error.
        /// </summary>
        static void EnableOpenXrFeatures(List<string> report)
        {
            var settingsType = FindType("UnityEngine.XR.OpenXR.OpenXRSettings");
            if (settingsType == null)
            {
                report.Add("OpenXR package not found — features left untouched.");
                return;
            }

            var forBuildTarget = FindMethod(settingsType, "GetSettingsForBuildTargetGroup", 1);
            var settings = InvokeSafe(forBuildTarget, null, new object[] { BuildTargetGroup.Android });

            if (settings == null)
            {
                report.Add(
                    "OpenXR settings unavailable — enable OpenXR for Android first, " +
                    "then enable 'Meta Quest Support' and the Oculus Touch profile " +
                    "under Project Settings > XR Plug-in Management > OpenXR.");
                return;
            }

            var getFeatures = FindMethod(settings.GetType(), "GetFeatures", 0);
            var features = InvokeSafe(getFeatures, settings, null) as System.Collections.IEnumerable;
            if (features == null)
            {
                report.Add(
                    "Could not enumerate OpenXR features — enable 'Meta Quest Support' " +
                    "manually under Project Settings > XR Plug-in Management > OpenXR.");
                return;
            }

            var enabled = new List<string>();
            foreach (var feature in features)
            {
                if (feature == null) continue;

                var typeName = feature.GetType().Name;
                if (typeName.IndexOf("MetaQuest", StringComparison.OrdinalIgnoreCase) < 0
                    && typeName.IndexOf("OculusTouch", StringComparison.OrdinalIgnoreCase) < 0)
                {
                    continue;
                }

                if (SetEnabledFlag(feature, true)) enabled.Add(typeName);
            }

            if (enabled.Count > 0)
            {
                var dirtyTarget = settings as UnityEngine.Object;
                if (dirtyTarget != null)
                {
                    EditorUtility.SetDirty(dirtyTarget);
                    AssetDatabase.SaveAssets();
                }

                report.Add("OpenXR features enabled: " + string.Join(", ", enabled) + ".");
            }
            else
            {
                report.Add(
                    "No Meta Quest features found — enable 'Meta Quest Support' and " +
                    "the Oculus Touch Controller Profile manually under Project " +
                    "Settings > XR Plug-in Management > OpenXR.");
            }
        }

        // ---- reflection helpers ------------------------------------------------

        static Type FindType(string assemblyQualifiedName)
        {
            var type = Type.GetType(assemblyQualifiedName);
            if (type != null) return type;

            var fullName = assemblyQualifiedName.Split(',')[0].Trim();
            foreach (var assembly in AppDomain.CurrentDomain.GetAssemblies())
            {
                type = assembly.GetType(fullName);
                if (type != null) return type;
            }

            return null;
        }

        static MethodInfo FindMethod(Type type, string name, int parameterCount)
        {
            if (type == null) return null;

            const BindingFlags flags =
                BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance;

            return type
                .GetMethods(flags)
                .FirstOrDefault(method => method.Name == name
                                          && method.GetParameters().Length == parameterCount);
        }

        static object TryGetConfigObject(Type configType, string key)
        {
            var tryGet = typeof(EditorBuildSettings)
                .GetMethods(BindingFlags.Public | BindingFlags.Static)
                .FirstOrDefault(method => method.Name == "TryGetConfigObject"
                                          && method.IsGenericMethodDefinition
                                          && method.GetParameters().Length == 2);

            if (tryGet == null || key == null) return null;

            var arguments = new object[] { key, null };
            var result = InvokeSafe(tryGet.MakeGenericMethod(configType), null, arguments);
            return result is bool found && found ? arguments[1] : null;
        }

        /// <summary>
        /// Reflection that logs instead of throwing: a package API that moved
        /// should degrade to a manual instruction, not abort the whole setup.
        /// </summary>
        static object InvokeSafe(MethodInfo method, object target, object[] arguments)
        {
            if (method == null) return null;

            try
            {
                return method.Invoke(target, arguments);
            }
            catch (Exception exception)
            {
                var inner = exception.InnerException ?? exception;
                Debug.LogWarning("[GriotVR] " + method.Name + " failed: " + inner.Message);
                return null;
            }
        }

        /// <summary>
        /// Sets <c>enabled</c> on an OpenXR feature; the flag lives on the
        /// OpenXRFeature base class and is not always public.
        /// </summary>
        static bool SetEnabledFlag(object feature, bool value)
        {
            for (var type = feature.GetType(); type != null; type = type.BaseType)
            {
                const BindingFlags flags =
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.DeclaredOnly;

                var property = type.GetProperty("enabled", flags);
                if (property != null && property.CanWrite)
                {
                    property.SetValue(feature, value);
                    return true;
                }

                var field = type.GetField("enabled", flags) ?? type.GetField("m_enabled", flags);
                if (field != null)
                {
                    field.SetValue(feature, value);
                    return true;
                }
            }

            return false;
        }
    }
}
