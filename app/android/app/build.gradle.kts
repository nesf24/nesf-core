import java.util.Properties
import java.io.FileInputStream
import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "in.nesportsfoundation.nesf_core"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "in.nesportsfoundation.nesf_core"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // ⚠️ SECURITY: Load keystore password from key.properties (gitignored)
    // DO NOT hardcode passwords here - use key.properties or environment variables
    // Signing config disabled - will be re-enabled when the path issue is resolved
    /*
    signingConfigs {
        create("release") {
            // Load from key.properties file or environment
            if (project.hasProperty("KEYSTORE_PASSWORD")) {
                // Environment variable (CI/CD)
                keyAlias = "nesf-core-key"
                keyPassword = project.property("KEY_PASSWORD") as String
                storeFile = file("../nesf-core-key.jks")
                storePassword = project.property("KEYSTORE_PASSWORD") as String
            } else if (file("../../android/key.properties").exists()) {
                // Local key.properties file (gitignored)
                val keystoreProperties = Properties()
                keystoreProperties.load(FileInputStream("../../android/key.properties"))
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file("../../android/" + (keystoreProperties["storeFile"] as String))
                storePassword = keystoreProperties["storePassword"] as String
            } else {
                // Fallback - will fail at build time (safer than using hardcoded password)
                logger.error("ERROR: key.properties not found")
                logger.error("Create key.properties from key.properties.example")
                logger.error("See: app/android/key.properties.example")
                throw GradleException("key.properties is missing - cannot sign release APK")
            }
        }
    }
    */

    buildTypes {
        release {
            // signingConfig = signingConfigs.getByName("release")  // Disabled - signing config commented out
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
