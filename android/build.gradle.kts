allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// build-tools 버전을 모든 모듈에 못박는다.
//
// AGP 9.0.1 은 36.0.0 을 기본값으로 고르는데, 2026-08-26 릴리스 빌드가 그 버전을
// 자동 설치하다가 중간에 끊겨 실행 파일이 하나도 없는 폴더가 남았다
// ("Installed Build Tools revision 36.0.0 is corrupted"). AGP 는 기본값 외의
// 버전을 스스로 고르지 않으므로 멀쩡한 36.1.0 이 있어도 쓰지 않는다.
//
// app 모듈에만 지정하면 부족하다. 플러그인 모듈(shared_preferences_android 등)은
// 각자 android 블록을 갖고 있어 그쪽이 다시 기본값을 집는다 - 실제로 app 을
// 고치자 오류가 :app 에서 :shared_preferences_android 로 옮겨 갔다.
subprojects {
    afterEvaluate {
        extensions
            .findByType(com.android.build.gradle.BaseExtension::class.java)
            ?.buildToolsVersion = "36.1.0"
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
