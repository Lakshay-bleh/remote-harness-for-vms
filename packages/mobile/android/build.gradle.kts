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

// A plugin that compiles against API 37 asks for platform "android-37", but the SDK ships it as "android-37.0": name the minor
// version so the platform is found (locally and on CI).
subprojects {
    afterEvaluate {
        extensions.findByType(com.android.build.api.dsl.CommonExtension::class.java)?.let { android ->
            if (android.compileSdk == 37 && android.compileSdkMinor == null) android.compileSdkMinor = 0
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
