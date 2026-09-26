import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Con -Pentorno=pruebas sale otra app ("Maker PRUEBAS") que se instala junto a la real
// y apunta al proyecto de pruebas (ver scripts/desplegar.py apk).
val entorno = (project.findProperty("entorno") as String?)?.trim().orEmpty()

// Firma propia del proyecto (secretos/, fuera de git). Con la misma llave, una versión nueva se
// instala encima de la anterior desde cualquier computadora. Sin ella se firma con la llave de
// depuración de esta PC, que solo sirve para probar: scripts/desplegar.py apk exige la propia.
val archivoFirma = rootProject.file("../../secretos/firma-android.properties")
val firma = Properties().apply { if (archivoFirma.exists()) archivoFirma.inputStream().use { load(it) } }

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
        // Android 7.0 o más nuevo (lo que pide Flutter 3.35; Firebase pide 6.0).
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (archivoFirma.exists()) {
            create("propia") {
                storeFile = archivoFirma.parentFile.resolve(firma.getProperty("storeFile"))
                storePassword = firma.getProperty("storePassword")
                keyAlias = firma.getProperty("keyAlias")
                keyPassword = firma.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (archivoFirma.exists()) "propia" else "debug")
        }
    }
}

flutter {
    source = "../.."
}
