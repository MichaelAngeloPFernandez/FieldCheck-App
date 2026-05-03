allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val relocatedRootBuildDir = rootProject.layout.projectDirectory.dir("../../build")
rootProject.layout.buildDirectory.set(relocatedRootBuildDir)

subprojects {
    layout.buildDirectory.set(relocatedRootBuildDir.dir(name))
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
