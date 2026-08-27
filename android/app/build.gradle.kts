plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.vica.vica_supervisor"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // AGP 9.0.1 은 build-tools 36.0.0 을 기본값으로 못박는다. 2026-08-26 릴리스
    // 빌드가 그 버전을 자동 설치하다가 중간에 끊겨 실행 파일이 하나도 없는
    // 폴더가 남았고("Installed Build Tools revision 36.0.0 is corrupted"),
    // 그 뒤로 디버그 빌드가 막혔다. AGP 는 기본값 외의 버전을 스스로 고르지
    // 않으므로 멀쩡히 설치된 36.1.0 이 있어도 쓰지 않는다.
    //
    // 값을 여기 고정하면 그 자동 선택을 건너뛴다. 팀원 PC 에서도 같은 버전을
    // 쓰게 되어 "내 컴퓨터에서는 되는데" 를 줄이는 효과도 있다.
    buildToolsVersion = "36.1.0"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.vica.vica_supervisor"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
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

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
