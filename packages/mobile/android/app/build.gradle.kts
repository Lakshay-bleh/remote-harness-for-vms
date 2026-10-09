import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Push (Firebase Cloud Messaging) needs android/app/google-services.json, which is not in the repository. Without it the app
// builds and runs; push stays off. See docs/ANDROID.md.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

// Which download this is (see docs/ANDROID.md):
//   flutter build apk                                   the normal download: no accessibility service (Play Protect blocks
//                                                       sideloaded apps that declare one)
//   flutter build apk -P phoneControl=true              the "with phone control" download (adds src/phonecontrol)
//   flutter build appbundle --release -P play=true      the Google Play build: phone control included (Play installs are not
//                                                       blocked), minus what Play does not allow this app (see src/play)
// The flags can also be set in android/gradle.properties (phoneControl=true / play=true).
val play = (project.findProperty("play") as String?) == "true"
val phoneControl = play || (project.findProperty("phoneControl") as String?) == "true"

// Release signing with the Play upload key. The key and its passwords never enter the repository: they are read from the file
// named by ESCANOR_SIGNING_PROPERTIES (default ~/.config/escanor-android/signing.properties) with storeFile, storePassword,
// keyAlias, keyPassword. Without it, release builds are signed with the debug key so they still install.
val signingFile = file(
    System.getenv("ESCANOR_SIGNING_PROPERTIES")
        ?: System.getenv("RH_SIGNING_PROPERTIES")
        ?: "${System.getProperty("user.home")}/.config/escanor-android/signing.properties",
)
val signing = Properties().apply { if (signingFile.exists()) signingFile.inputStream().use { load(it) } }
val hasUploadKey = !signing.getProperty("storeFile").isNullOrBlank()

android {
    namespace = "com.escanorlabs.escanor"
    // permission_handler_android compiles against API 37, which the SDK ships as platform "android-37.0".
    compileSdk = 37
    compileSdkMinor = 0
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications uses java.time on older Android
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.escanorlabs.escanor"
        // firebase_messaging, mobile_scanner and permission_handler need Android 7.0 (API 24) or newer
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    sourceSets {
        // The accessibility service (phone control) is declared only in these variants; its code is always compiled, so the
        // settings screen can say whether it is in this download.
        if (phoneControl) {
            val manifest = if (play) "src/play/AndroidManifest.xml" else "src/phonecontrol/AndroidManifest.xml"
            for (type in listOf("debug", "profile", "release")) {
                findByName(type)?.apply {
                    this.manifest.srcFile(manifest)
                    res.srcDir("src/phonecontrol/res")
                }
            }
        }
    }

    signingConfigs {
        if (hasUploadKey) {
            create("upload") {
                storeFile = file(signing.getProperty("storeFile"))
                storePassword = signing.getProperty("storePassword")
                keyAlias = signing.getProperty("keyAlias")
                keyPassword = signing.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (hasUploadKey) "upload" else "debug")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    packaging {
        // 16 KB pages (Android 15+, required by Google Play): keep native libraries uncompressed and page-aligned in the APK.
        jniLibs {
            useLegacyPackaging = false
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation("androidx.core:core-ktx:1.17.0")
    // "Hey Escanor": speech recognition that runs on the phone (the voice model is downloaded once, when the person turns it on).
    // 0.3.75 and JNA 5.19.1 ship 16 KB-aligned native libraries, which Google Play requires (Android 15+ 16 KB page size).
    implementation("com.alphacephei:vosk-android:0.3.75") {
        exclude(group = "net.java.dev.jna", module = "jna")
    }
    implementation("net.java.dev.jna:jna:5.19.1@aar")
    // JVM unit tests of the native side (src/test): cd android && ./gradlew :app:testDebugUnitTest
    testImplementation("junit:junit:4.13.2")
}
