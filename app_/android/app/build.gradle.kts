import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingProperties = Properties().apply {
    val signingPropertiesFile = rootProject.file("key.properties")
    if (signingPropertiesFile.exists()) {
        signingPropertiesFile.inputStream().use(::load)
    }
}

fun signingValue(envName: String, propertyName: String): String? {
    val envValue = providers.environmentVariable(envName).orNull?.trim()
    if (!envValue.isNullOrEmpty()) {
        return envValue
    }

    val propertyValue = signingProperties.getProperty(propertyName)?.trim()
    return propertyValue?.takeIf { it.isNotEmpty() }
}

val releaseStoreFilePath = signingValue("ANDROID_KEYSTORE_PATH", "storeFile")
val releaseStorePassword = signingValue("ANDROID_KEYSTORE_PASSWORD", "storePassword")
val releaseKeyAlias = signingValue("ANDROID_KEY_ALIAS", "keyAlias")
val releaseKeyPassword = signingValue("ANDROID_KEY_PASSWORD", "keyPassword")
val releaseStoreFile = releaseStoreFilePath?.let { file(it) }

val releaseSigningConfigured =
    releaseStoreFile != null &&
        releaseStoreFile.exists() &&
        !releaseStorePassword.isNullOrEmpty() &&
        !releaseKeyAlias.isNullOrEmpty() &&
        !releaseKeyPassword.isNullOrEmpty()
val unsignedReleaseAllowed =
    providers.environmentVariable("RONIKDRIVE_ALLOW_UNSIGNED_ANDROID_RELEASE").orNull == "true"

val releaseTaskRequested = gradle.startParameter.taskNames.any { taskName ->
    val normalizedTaskName = taskName.lowercase()
    normalizedTaskName.contains("release") || normalizedTaskName.contains("bundle")
}

android {
    namespace = "com.cloudstorage.cloud_storage"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    dependencies {
        coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.cloudstorage.cloud_storage"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (releaseSigningConfigured) {
                storeFile = releaseStoreFile
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }


    buildTypes {
        release {
            if (releaseSigningConfigured && !unsignedReleaseAllowed) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

if (releaseTaskRequested && !releaseSigningConfigured && !unsignedReleaseAllowed) {
    val missingInputs = buildList {
        if (releaseStoreFilePath.isNullOrEmpty()) {
            add("ANDROID_KEYSTORE_PATH/storeFile")
        } else if (releaseStoreFile == null || !releaseStoreFile.exists()) {
            add("keystore file at $releaseStoreFilePath")
        }
        if (releaseStorePassword.isNullOrEmpty()) {
            add("ANDROID_KEYSTORE_PASSWORD/storePassword")
        }
        if (releaseKeyAlias.isNullOrEmpty()) {
            add("ANDROID_KEY_ALIAS/keyAlias")
        }
        if (releaseKeyPassword.isNullOrEmpty()) {
            add("ANDROID_KEY_PASSWORD/keyPassword")
        }
    }
    throw GradleException(
        "Android release signing is not configured. Missing: ${missingInputs.joinToString()}. " +
            "Provide CI env vars or create android/key.properties from android/key.properties.example."
    )
}

flutter {
    source = "../.."
}
