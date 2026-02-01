import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    // 1. SECURE PROPERTY LOADER
    val keystoreProperties = Properties()
    val keystorePropertiesFile = rootProject.file("key.properties")
    
    if (keystorePropertiesFile.exists()) {
        FileInputStream(keystorePropertiesFile).use { stream ->
            keystoreProperties.load(stream)
        }
        println("S.INC AUDIT: key.properties found and loaded.")
    }

    namespace = "com.sinc.procrastinator"
    compileSdk = 36 
    ndkVersion = flutter.ndkVersion

    // 2. SIGNING CONFIGURATIONS
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        // Suppressing the deprecation warning for jvmTarget
        @Suppress("DEPRECATION")
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.sinc.procrastinator"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

   buildTypes {
        // 1. THE PRODUCTION SEAL
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            
            isMinifyEnabled = true
            isShrinkResources = false
            setProperty("archivesBaseName", "sinc-procrastinator")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }

        // 2. THE DEVELOPMENT OVERRIDE
        // We use the shorthand "debug" here to ensure it overrides the internal default
        debug {
            // Point this specifically to your "release" config defined in signingConfigs
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // 🛡️ S.INC SHIELD: Modern 2026 Library Desugaring
add("coreLibraryDesugaring", "com.android.tools:desugar_jdk_libs:2.1.4")
}