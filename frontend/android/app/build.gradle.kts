import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing.
//
// This build used to sign release builds with the Android debug keystore. That
// key ships in the AOSP source tree, so it is public: anyone could produce an
// update that a device running this app would accept as authentic. Signing is
// the only thing standing between a published app and an arbitrary code
// execution on every device that installed it, so a release build now refuses
// to run without a real key rather than quietly producing a debug-signed APK.
//
// Configure by creating android/key.properties (already git-ignored along with
// *.jks / *.keystore):
//
//   storePassword=<password from `keytool`>
//   keyPassword=<password from `keytool`>
//   keyAlias=<alias>
//   storeFile=/absolute/path/to/upload-keystore.jks
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

// Whether this invocation is actually assembling a release artifact. The
// `buildTypes` block below is evaluated for every build, including debug, so the
// failure has to be conditional on the requested tasks or it would break local
// development. `flutter build apk/bundle --release` maps onto assembleRelease /
// bundleRelease.
val assemblingRelease = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}

android {
    namespace = "org.africanteller.african_teller"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "org.africanteller.african_teller"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            } else if (assemblingRelease) {
                throw GradleException(
                    """
                    |Refusing to build a release APK: no signing key is configured.
                    |
                    |A release build signed with the Android debug keystore is not a
                    |release build. The debug key is published in the AOSP source tree, so
                    |anyone could sign an update that this app would install and run.
                    |
                    |Create android/key.properties (git-ignored) alongside an upload key:
                    |
                    |  keytool -genkey -v -keystore upload-keystore.jks \
                    |    -keyalg RSA -keysize 2048 -validity 10000 -alias upload
                    |
                    |  storePassword=<store password>
                    |  keyPassword=<key password>
                    |  keyAlias=upload
                    |  storeFile=/absolute/path/to/upload-keystore.jks
                    |
                    |For a local smoke build use a debug build instead:
                    |  flutter build apk --debug
                    """.trimMargin(),
                )
            }
            // With no keystore and no release task in flight this is a debug
            // build; it keeps the debug signing config.
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
