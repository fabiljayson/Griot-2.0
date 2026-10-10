using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using Griot.VR.MobileVR;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEngine;

namespace Griot.VR.EditorTools
{
    /// <summary>
    /// Three build-switch menu items for the phone APK (§18 of the Mobile
    /// VR spec): take OpenXR off Android for a SHINECON validation build,
    /// put it back for a headset build, and flip the <c>USE_MOCK_API</c>
    /// define so a validation APK stubs the backend instead of reaching the
    /// deployed API.
    /// </summary>
    /// <remarks>
    /// OpenXR packages are never removed from the project — only the
    /// Android loader assignment changes, through the same reflection
    /// approach as <see cref="GriotVrProjectSetup"/> so a moved package API
    /// degrades to a printed instruction instead of a compile error. The
    /// Bootstrap's own runtime mode (Auto / MobileVR / HeadsetVR) is the
    /// second, independent switch; the loader toggle simply removes the
    /// runtime XR session that Auto would otherwise pick.
    /// </remarks>
    public static class GriotVrMobileBuild
    {
        const string OpenXrLoaderType = "UnityEngine.XR.OpenXR.OpenXRPackage";
        const string LogPrefix = "[GriotVR] ";
        const string PhoneApkPath = "Builds/GriotVR-Phone.apk";

        /// <summary>
        /// One-shot phone APK: also the batch entry point
        /// (<c>-batchmode -buildTarget Android -executeMethod
        /// Griot.VR.EditorTools.GriotVrMobileBuild.BuildPhoneApk</c>).
        /// Re-runs the OpenXR disable step, writes the scene list — a mirror
        /// of <c>GriotVrProjectSetup.RequiredScenes</c>, which the batch
        /// environment has never run — and throws on any build failure so
        /// batch mode exits non-zero.
        /// </summary>
        [MenuItem("Tools/Griot/Mobile VR: Build Phone APK")]
        public static void BuildPhoneApk()
        {
            DisableOpenXrForAndroid();

            var scenes = new[]
            {
                "Assets/Scenes/Bootstrap.unity",
                "Assets/Scenes/Loading.unity",
                "Assets/Scenes/CameroonHeritageMuseum.unity",
                "Assets/Scenes/Museum.unity",
            };

            var missing = scenes.Where(scene => !File.Exists(scene)).ToArray();
            if (missing.Length > 0)
                throw new BuildFailedException(LogPrefix + "missing scenes: " + string.Join(", ", missing));

            EditorBuildSettings.scenes = scenes
                .Select(path => new EditorBuildSettingsScene(path, true))
                .ToArray();

            Directory.CreateDirectory(Path.GetDirectoryName(PhoneApkPath));

            var summary = BuildPipeline
                .BuildPlayer(scenes, PhoneApkPath, BuildTarget.Android, BuildOptions.None)
                .summary;

            if (summary.result != BuildResult.Succeeded)
                throw new BuildFailedException(LogPrefix + "phone APK build " + summary.result +
                    " (" + summary.totalErrors + " errors, " + summary.totalTime + ")");

            Debug.Log(LogPrefix + "phone APK built: " + Path.GetFullPath(PhoneApkPath) +
                " (" + summary.totalSize + " bytes)");
        }

        [MenuItem("Tools/Griot/Mobile VR: Disable OpenXR for Android (Phone APK)")]
        public static void DisableOpenXrForAndroid()
        {
            var manager = TryGetAndroidXrManager();
            if (manager == null) return;

            var activeLoaders = manager.GetType()
                .GetProperty("activeLoaders", BindingFlags.Public | BindingFlags.Instance)
                ?.GetValue(manager) as System.Collections.IEnumerable;
            if (activeLoaders == null)
            {
                Report("Could not enumerate XR loaders — disable OpenXR manually in " +
                       "Project Settings > XR Plug-in Management > Android.");
                return;
            }

            object openXrLoader = null;
            foreach (var loader in activeLoaders)
            {
                if (loader != null &&
                    loader.GetType().Name.IndexOf("OpenXR", StringComparison.OrdinalIgnoreCase) >= 0)
                {
                    openXrLoader = loader;
                    break;
                }
            }

            if (openXrLoader == null)
            {
                Report("OpenXR is not assigned for Android — the project is already in phone mode.");
                return;
            }

            var removeLoader = FindMethod(manager.GetType(), "TryRemoveLoader", 1);
            var removed = InvokeSafe(removeLoader, manager, new[] { openXrLoader });
            Report(removed is bool ok && ok
                ? "OpenXR loader removed for Android: phone APK will not start an XR session."
                : "Could not remove the OpenXR loader — toggle it off in Project Settings > " +
                  "XR Plug-in Management > Android.");
        }

        [MenuItem("Tools/Griot/Mobile VR: Enable OpenXR for Android (Headset APK)")]
        public static void EnableOpenXrForAndroid()
        {
            var manager = TryGetAndroidXrManager();
            if (manager == null) return;

            var metadataType = FindType("UnityEditor.XR.Management.Metadata.XRPackageMetadataStore");
            var assignLoader = FindMethod(metadataType, "AssignLoader", 3);
            var assigned = InvokeSafe(assignLoader, null, new object[]
            {
                manager, OpenXrLoaderType, BuildTargetGroup.Android,
            });

            Report(assigned is bool ok && ok
                ? "OpenXR loader assigned for Android: headset APK path restored."
                : "Could not assign the OpenXR loader — enable it in Project Settings > " +
                  "XR Plug-in Management > Android.");
        }

        /// <summary>
        /// Android-only define toggle. Checked state is shown by the menu
        /// checkmark; enabling it also forces the phone runtime in the
        /// bootstrap's Auto mode and stubs the API (see
        /// <see cref="MobileVRTestMode"/>).
        /// </summary>
        [MenuItem("Tools/Griot/Mobile VR: USE_MOCK_API (Android)")]
        public static void ToggleMockApiDefine()
        {
            var target = NamedBuildTarget.FromBuildTargetGroup(BuildTargetGroup.Android);
            var symbols = PlayerSettings.GetScriptingDefineSymbols(target) ?? string.Empty;
            var parts = symbols.Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries)
                .Where(part => part != MobileVRTestMode.DefineSymbol)
                .ToList();

            var enabling = !symbols.Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries)
                .Contains(MobileVRTestMode.DefineSymbol);

            if (enabling) parts.Add(MobileVRTestMode.DefineSymbol);

            PlayerSettings.SetScriptingDefineSymbols(
                target, string.Join(";", parts));

            Report(enabling
                ? MobileVRTestMode.DefineSymbol + " set for Android: validation builds stub the API and force the phone runtime."
                : MobileVRTestMode.DefineSymbol + " cleared for Android: live API and normal runtime selection.");
        }

        [MenuItem("Tools/Griot/Mobile VR: USE_MOCK_API (Android)", true)]
        static bool ToggleMockApiDefineValidate()
        {
            var target = NamedBuildTarget.FromBuildTargetGroup(BuildTargetGroup.Android);
            var symbols = PlayerSettings.GetScriptingDefineSymbols(target) ?? string.Empty;
            return symbols.Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries)
                .Contains(MobileVRTestMode.DefineSymbol);
        }

        // ---- reflection helpers (mirrors GriotVrProjectSetup) ----------------

        static object TryGetAndroidXrManager()
        {
            const BindingFlags staticFlags = BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic;

            var generalType = FindType("UnityEngine.XR.Management.XRGeneralSettings");
            var perTargetType = FindType("UnityEditor.XR.Management.XRGeneralSettingsPerBuildTarget");

            if (generalType == null || perTargetType == null)
            {
                Report("XR Management not found — open Project Settings > XR Plug-in " +
                       "Management once, then re-run this item.");
                return null;
            }

            var keyField = generalType.GetField("k_SettingsKey", staticFlags);
            var key = keyField != null ? keyField.GetValue(null) as string : null;
            var perTarget = TryGetConfigObject(perTargetType, key);
            if (perTarget == null)
            {
                Report("XR Plug-in Management has not been initialised — open Project " +
                       "Settings > XR Plug-in Management once, then re-run this item.");
                return null;
            }

            var getSettings = FindMethod(perTargetType, "SettingsForBuildTarget", 1)
                              ?? FindMethod(perTargetType, "GetSettingsForBuildTarget", 1);
            var androidSettings = InvokeSafe(getSettings, perTarget, new object[] { BuildTargetGroup.Android });
            if (androidSettings == null)
            {
                Report("No Android XR settings — open Project Settings > XR Plug-in " +
                       "Management > Android once, then re-run this item.");
                return null;
            }

            var managerProperty = androidSettings.GetType()
                .GetProperty("Manager", BindingFlags.Public | BindingFlags.Instance);
            var manager = managerProperty != null ? managerProperty.GetValue(androidSettings) : null;
            if (manager == null)
            {
                Report("XR Manager missing — open Project Settings > XR Plug-in " +
                       "Management > Android once, then re-run this item.");
            }

            return manager;
        }

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
                Debug.LogWarning(LogPrefix + method.Name + " failed: " + inner.Message);
                return null;
            }
        }

        static void Report(string message)
        {
            Debug.Log(LogPrefix + message);
        }
    }
}
