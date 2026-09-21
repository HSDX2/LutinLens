# App 正式签名（替换 debug 签名）

> 当前 release 用的是 **debug 签名**（`android/app/build.gradle` 里 `signingConfig signingConfigs.debug`），能装能用，但**不能上架、不能覆盖正式版**。下面换成你自己的正式签名。

## 1. 生成 keystore

（需要 JDK 的 keytool，装 Flutter/Android Studio 时已带）

```bash
keytool -genkey -v -keystore upload-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

- 会提示设置 keystore 密码、key 密码、姓名组织等。**记牢密码**。
- 生成的 `upload-key.jks` **不要提交到 git**（后面会进 .gitignore）。

## 2. 创建 android/key.properties

```
storePassword=你的keystore密码
keyPassword=你的key密码
keyAlias=upload
storeFile=/绝对路径/upload-key.jks
```

⚠️ 这个文件含密码，**必须加入 .gitignore**。

## 3. 修改 android/app/build.gradle

在 `android {` 之前加载 key.properties，并让 release 用正式签名：

```groovy
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

android {
    // ... 原有内容不动 ...
    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword keystoreProperties['storePassword']
        }
    }
    buildTypes {
        release {
            signingConfig signingConfigs.release   // 原来这里是 signingConfigs.debug
        }
    }
}
```

## 4. .gitignore 加两行

```
android/key.properties
*.jks
```

## 5. 重新打包

```bash
flutter build apk --release
# 产物 build/app/outputs/flutter-apk/app-release.apk 已是正式签名
```

## 注意

- **覆盖安装**：手机上若已装过 debug 签名版，需先卸载再装正式版（签名不同无法覆盖）。
- **上架**：正式签名的 APK/AAB 才能上架 Google Play 等商店；AAB 用 `flutter build appbundle`。
- **安全**：keystore 和 key.properties 丢了/泄露就无法再更新已上架应用，务必备份。