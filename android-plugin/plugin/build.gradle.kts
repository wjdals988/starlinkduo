plugins {
    id("com.android.library")
}

val pluginName = "StarlinkBluetooth"
val pluginPackageName = "com.starlinkduo.bluetooth"

android {
    namespace = pluginPackageName
    // Keep AAR metadata compatible with Godot 4.7.2's Android template.
    compileSdk = 36

    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        minSdk = 31
        manifestPlaceholders["godotPluginName"] = pluginName
        buildConfigField("String", "GODOT_PLUGIN_NAME", "\"$pluginName\"")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    lint {
        disable += "GradleDependency"
    }

}

dependencies {
    implementation("org.godotengine:godot:4.7.2.stable")
}
