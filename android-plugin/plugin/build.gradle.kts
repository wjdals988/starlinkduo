plugins {
    id("com.android.library")
}

val pluginName = "StarlinkBluetooth"
val pluginPackageName = "com.starlinkduo.bluetooth"

android {
    namespace = pluginPackageName
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

}

dependencies {
    implementation("org.godotengine:godot:4.7.2.stable")
}
