plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.ludotitan"
    
    // CRITICAL FIX: Explicitly set to 34 for Android 11+ support
    compileSdk = 35
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.ludotitan"
        
        // CRITICAL FIX: Set minimum SDK to 21 (Android 5.0) for WebView support
        minSdk = flutter.minSdkVersion
        
        // CRITICAL FIX: Set target SDK to 34 for Android 11+ compatibility
        targetSdk = 34
        
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        // ADDED: Enable multidex for apps with many dependencies
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // Add ProGuard rules for release builds
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            // Signing with the debug keys for now
            signingConfig = signingConfigs.getByName("debug")
        }
        debug {
            // Useful for debugging
            isDebuggable = true
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ADDED: Multidex support for handling many dependencies
    implementation("androidx.multidex:multidex:2.0.1")
}
