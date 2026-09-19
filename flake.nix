{
  description = "LutinLens development shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }: 
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
        jdkHome = "${pkgs.openjdk17}/Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home";
      in {
        devShell = pkgs.mkShell {
          buildInputs = [
            pkgs.openjdk17
            pkgs.maven
          ];

          shellHook = ''
            # 设置本地 Flutter SDK 目录
            LOCAL_FLUTTER_SDK="$HOME/.flutter-sdk"
            
            # 检查本地 Flutter SDK 是否存在
            if [ ! -d "$LOCAL_FLUTTER_SDK" ]; then
              echo "❌ Local Flutter SDK not found at $LOCAL_FLUTTER_SDK"
              echo "Please clone Flutter manually:"
              echo "git clone https://github.com/flutter/flutter.git -b 3.24.0 ~/.flutter-sdk"
              exit 1
            fi


            export JAVA_HOME=${jdkHome}
            # 使用本地Flutter SDK，它自带Dart，不需要单独的Dart
            export PATH="$JAVA_HOME/bin:$LOCAL_FLUTTER_SDK/bin:$PATH"

            export FLUTTER_ROOT="$LOCAL_FLUTTER_SDK"
            export DART_SDK="$LOCAL_FLUTTER_SDK/bin/cache/dart-sdk"
            export PUB_CACHE="''${PUB_CACHE:-$HOME/.pub-cache}"

            # 确保 Gradle 用这个 JDK，而不是系统的
            export GRADLE_OPTS="-Dorg.gradle.java.home=$JAVA_HOME $GRADLE_OPTS"
            
            # 设置 Gradle 用户目录到可写位置
            export GRADLE_USER_HOME="$HOME/.gradle"

            echo "🚀 Flutter/Dart environment loaded"
            echo "📁 Flutter SDK: $LOCAL_FLUTTER_SDK"
            java -version
            flutter --version
          '';
        };
      }
    );
}
