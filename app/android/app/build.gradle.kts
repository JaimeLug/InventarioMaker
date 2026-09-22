plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Con -Pentorno=pruebas sale otra app ("Maker PRUEBAS") que se instala junto a la real
// y apunta al proyecto de pruebas (ver scripts/desplegar.py apk).
val entorno = (project.findProperty("entorno") as String?)?.trim().orEmpty()

android {
    namespace = "mx.edu.prepa13.inventario_maker"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "mx.edu.prepa13.inventario_maker" + if (entorno.isEmpty()) "" else ".$entorno"
        resValue("string", "app_name", if (entorno.isEmpty()) "Inventario Maker" else "Maker ${entorno.uppercase()}")
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Firebase (avisos al celular) pide Android 6.0 o más nuevo.
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
