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
    project.evaluationDependsOn(":app")
}

// AGP 8+ requires every Android module to declare a `namespace`. Legacy Flutter
// plugins (e.g. contacts_service 0.6.3) predate this and omit it, which breaks
// configuration. Inject the namespace from the plugin's group (its manifest
// package) when a module does not declare one itself.
subprojects {
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.gradle.LibraryExtension>("android") {
            if (namespace == null) {
                namespace = (project.group?.toString()
                        ?.takeIf { it.isNotBlank() && it != "unspecified" })
                    ?: "flutter.plugins.contactsservice.contactsservice"
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
