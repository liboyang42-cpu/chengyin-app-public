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
subprojects {
    // 某些第三方插件(如 amap_map)把自身 compileSdk 钉死在 android-35,
    // 而其依赖 flutter_plugin_android_lifecycle 要求 36+,导致 checkAarMetadata 失败。
    // 把这些插件子模块的 compileSdk 抬到 36。
    // 注意:跳过 :app —— evaluationDependsOn(":app") 会让 :app 提前求值,
    // 再对它注册 afterEvaluate 会报 "already evaluated";且 :app 本就是 36。
    if (project.name != "app") {
        afterEvaluate {
            val androidExt = project.extensions.findByName("android")
                as? com.android.build.gradle.BaseExtension
            if (androidExt != null) {
                val current = androidExt.compileSdkVersion
                    ?.substringAfter("android-")
                    ?.toIntOrNull() ?: 0
                if (current < 36) {
                    androidExt.compileSdkVersion(36)
                }
            }
        }
    }
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
