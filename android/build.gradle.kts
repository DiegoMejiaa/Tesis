allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Redirige el directorio de build fuera de cada módulo (plantilla de Flutter).
val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// ---------------------------------------------------------------------------
//  Compatibilidad de plugins ANTIGUOS con AGP 9 / Gradle 9 / Flutter 3.44.
//  (p. ej. flutter_bluetooth_serial 0.4.0, de 2021)
//
//  Parchea cada subproyecto Android que lo necesite:
//    1) namespace  -> lo exige AGP 8+; muchos plugins viejos no lo declaran.
//    2) compileSdk -> AGP 9 rechaza valores obsoletos (el plugin trae 30);
//                     se sube al mismo compileSdk del módulo :app.
//    3) buildTools -> evita "Failed to find Build Tools revision 30.0.3"
//                     forzando el del módulo :app.
//
//  El parche se ejecuta DESPUÉS de evaluar el subproyecto. El guard
//  `state.executed` evita el error
//      "Cannot run Project.afterEvaluate(Action) when the project is
//       already evaluated"
//  que aparece cuando evaluationDependsOn(":app") ya forzó la evaluación
//  antes de que llegáramos a registrar el afterEvaluate.
// ---------------------------------------------------------------------------
subprojects {
    val parchearCompatibilidad: () -> Unit = parche@{
        val ext = project.extensions.findByName("android")
                as? com.android.build.gradle.BaseExtension ?: return@parche

        if (ext.namespace == null) {
            ext.namespace = project.group.toString()
        }

        // El módulo :app ya define compileSdk/buildTools vía Flutter: no se toca.
        if (project.path != ":app") {
            val appExt = rootProject.project(":app").extensions.findByName("android")
                    as? com.android.build.gradle.BaseExtension
            appExt?.compileSdkVersion?.let { ext.compileSdkVersion(it) }
            appExt?.buildToolsVersion?.let { ext.buildToolsVersion = it }
        }
    }

    // Si el proyecto ya fue evaluado, parchea de inmediato; si no, al evaluar.
    if (state.executed) parchearCompatibilidad() else afterEvaluate { parchearCompatibilidad() }
}

// Plantilla de Flutter: garantiza que :app se evalúe antes que los plugins.
// Va DESPUÉS del bloque de parcheo para que el afterEvaluate quede registrado
// antes de que esta línea fuerce la evaluación.
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
