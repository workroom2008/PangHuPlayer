allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Redirect all build outputs to the project-level build directory.
// This is necessary because the Pub cache directory is read-only in the TRAE sandbox,
// and any plugin that tries to write to its own build/ folder inside the cache will fail.
val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// Force compileSdk = 36 for all Android subprojects.
subprojects {
    afterEvaluate {
        if (plugins.hasPlugin("com.android.library")) {
            extensions.configure<com.android.build.api.dsl.LibraryExtension>("android") {
                compileSdk = 36
            }
        }
        if (plugins.hasPlugin("com.android.application")) {
            extensions.configure<com.android.build.api.dsl.ApplicationExtension>("android") {
                compileSdk = 36
            }
        }
    }
}

// For the :jni module, replace CMake native build with prebuilt .so files.
// The jni plugin's CMake build fails in the TRAE sandbox due to file access restrictions
// inside the Pub cache directory. We manually compile the native library with the NDK
// and provide it as a prebuilt jniLibs source set instead.
subprojects {
    if (project.name == "jni") {
        // Add prebuilt jniLibs source directory
        plugins.withId("com.android.library") {
            extensions.configure<com.android.build.api.dsl.LibraryExtension>("android") {
                sourceSets.getByName("main") {
                    jniLibs {
                        srcDir("D:/Trae CN/torrent/player/lanplayer/build/jni_native_prebuilt")
                    }
                }
            }
        }
        // Disable all CMake configure/build tasks because they fail in the sandbox
        tasks.whenTaskAdded {
            if (name.startsWith("configureCMake") || name.startsWith("buildCMake") ||
                name.startsWith("externalNativeBuild") || name.startsWith("mergeCxx")) {
                enabled = false
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
