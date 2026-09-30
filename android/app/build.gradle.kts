import java.util.Properties
import java.io.FileInputStream

// 正式签名配置。★ 密钥**不进仓库** —— android/.gitignore 已挡掉
// key.properties / *.jks / *.keystore。缺文件时不报错,回退 debug 签名,
// 这样别人 clone 下来仍能 `flutter run`;但**发布包必须有它**,
// 否则签名对不上工信部 App 备案里登记的公钥与证书 MD5 指纹。
//
// key.properties 格式(放在 android/ 目录下):
//   storeFile=/Users/你/chengyin-release.jks
//   storePassword=***
//   keyAlias=chengyin
//   keyPassword=***
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) load(FileInputStream(f))
}
val hasReleaseKey = keystoreProperties.getProperty("storeFile") != null

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.chengyinhub.chengyin_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.chengyinhub.chengyin_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // ⚠️ 没有 key.properties 时回退 debug 签名,只为让本地
            //    `flutter run --release` 能跑。**这种包不能上架、也不能用来备案**:
            //    备案登记的公钥/证书 MD5 必须与上架包一致,debug key 一换就对不上。
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                // ★★★ 必须吼一声,而且要**吼得到**。
                //   2026-08-20 实测:原来用的 `logger.warn` **被 Flutter 的构建输出
                //   整个吞掉** —— 完整构建日志里一个字都没有。
                //   也就是说这个"安全网"本身是个**假保证**:代码在、看着像有防护,
                //   实际永远到不了人眼前。而构建**一声不响地成功**、产出的文件
                //   还叫 app-release.apk,太容易被当成能上架的包
                //   (实测 apksigner 报 CN=Android Debug)。
                //
                //   改成两条都做,任一条都足以被发现:
                //   ① println 走标准输出 —— 比 logger.warn 更难被过滤掉
                //   ② **在产物旁边落一个标记文件** —— 它不依赖任何日志通道,
                //      看目录就能看见,CI 也能直接判它存在与否
                println(
                    "\n" +
                    "############################################################\n" +
                    "# 警告:release 包正在用 **调试证书** 签名                  #\n" +
                    "#   缺 android/key.properties ⇒ 回退 debug key。            #\n" +
                    "#   产出的 app-release.apk **不能上架、不能用于备案** ——    #\n" +
                    "#   备案登记的证书 MD5 必须与上架包一致,debug key 对不上。  #\n" +
                    "#   验证办法:apksigner verify --print-certs <apk>            #\n" +
                    "############################################################\n"
                )
                signingConfigs.getByName("debug")
            }
        }
    }
}

// ★★★ 调试签名的**可观测标记**。
//   日志会被吞(实测 logger.warn 在 Flutter 构建里一个字都不出),
//   但文件不会 —— 看一眼产物目录就知道这个包能不能上架,CI 也能直接判它在不在。
//   有真 key 时反过来:构建会把这个文件删掉,所以「文件还在」= 这次仍是 debug 签名。
tasks.whenTaskAdded {
    if (name == "assembleRelease" || name == "bundleRelease") {
        doLast {
            val marker = File(
                rootProject.projectDir.parentFile,
                "build/app/outputs/DEBUG_SIGNED_DO_NOT_SHIP.txt"
            )
            if (hasReleaseKey) {
                // 有真 key:把上一次留下的标记清掉,否则它会变成过期证据
                //(比没有标记更坏 —— 会让人以为一个能上架的包不能上架)。
                marker.delete()
            } else {
                marker.parentFile?.mkdirs()
                marker.writeText(
                    "这次 release 构建用的是 **调试证书**(缺 android/key.properties)。\n" +
                    "· 这个包不能上架、也不能用于 ICP 备案 ——\n" +
                    "  备案登记的证书 MD5 必须与上架包一致,debug key 对不上。\n" +
                    "· 生成真 keystore:bash tool/make_release_keystore.sh(密码只你自己知道)\n" +
                    "· 验证签名:apksigner verify --print-certs <apk>\n" +
                    "· ⚠️ 高德 Android Key 绑的是签名 SHA1 —— 必须先有真 keystore,再去申请 Key。\n"
                )
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
