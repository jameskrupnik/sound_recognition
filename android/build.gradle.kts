group = "com.jameskrupnik.sound_recognition"
version = "0.1.0"

buildscript {
    val kotlinVersion = "2.3.20"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.0.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "com.jameskrupnik.sound_recognition"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
        // The test clips live once, in tool/test_audio, for the desktop
        // scripts and this instrumented test alike.
        getByName("androidTest") {
            assets.srcDirs("../tool/test_audio")
            java.srcDirs("src/androidTest/kotlin")
        }
    }

    defaultConfig {
        minSdk = 24
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // LiteRT 1.4.2, 2026-03-11 — TensorFlow Lite under its new name. Chosen
    // over MediaPipe Tasks' tasks-audio 1.0.0 because MediaPipe reports usage
    // metrics to Google (see YamnetClassifier.kt); this has no transitive
    // dependencies at all and no telemetry. Pinned to the 1.x line on
    // purpose: 2.x keeps the same Interpreter but adds a GPU accelerator .so,
    // Guava, coroutines and a model-delivery library this does not use.
    // Its native libraries are 16 KB page-aligned, which Play requires for
    // targetSdk 35+.
    implementation("com.google.ai.edge.litert:litert:1.4.2")
    implementation("androidx.core:core:1.13.1")

    testImplementation("junit:junit:4.13.2")

    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
}
