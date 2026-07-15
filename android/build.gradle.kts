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

    // ── Arreglo para paquetes sin namespace (AGP 8+) ──
    // Se aplica ANTES de evaluar, para no chocar con evaluationDependsOn.
    project.plugins.withId("com.android.library") {
        val ext = project.extensions.findByName("android")
        if (ext != null) {
            try {
                val getter = ext.javaClass.getMethod("getNamespace")
                if (getter.invoke(ext) == null) {
                    val setter = ext.javaClass.getMethod("setNamespace", String::class.java)
                    setter.invoke(ext, project.group.toString())
                }
            } catch (e: Exception) {
                // Ignorar si el paquete no usa namespace
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