allprojects {
    repositories {
        google()
        mavenCentral()
    }
    dependencies.components {
        withModule("org.apache.httpcomponents:httpmime") {
            if (id.version == "4.5.6") {
                allVariants {
                    withDependencies {
                        filter {
                            it.group == "org.apache.httpcomponents" &&
                                it.name == "httpclient" &&
                                it.versionConstraint.requiredVersion == "4.5.6"
                        }.forEach {
                            it.version { require("4.5.14") }
                            it.because("CVE-2020-13956 is fixed in Apache HttpClient 4.5.13 and later")
                        }
                    }
                }
            }
        }
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
    tasks.configureEach {
        if (path == ":app_links:extractReleaseAnnotations") {
            doFirst("verifySafeAppLinksLintClasspath") {
                val inputNames = inputs.files.files.map { it.name }.toSet()
                val httpClientJars =
                    inputNames
                        .filter { it.startsWith("httpclient-") && it.endsWith(".jar") }
                        .sorted()
                val codecJars =
                    inputNames
                        .filter { it.startsWith("commons-codec-") && it.endsWith(".jar") }
                        .sorted()
                check(httpClientJars == listOf("httpclient-4.5.14.jar")) {
                    "Unexpected Apache HttpClient lint classpath: $httpClientJars"
                }
                check(codecJars == listOf("commons-codec-1.11.jar")) {
                    "Unexpected Commons Codec lint classpath: $codecJars"
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
