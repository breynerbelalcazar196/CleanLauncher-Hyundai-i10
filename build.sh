#!/bin/sh
set -e
cd "$(dirname "$0")"

MIN_SDK=25
TARGET_SDK=28
APK_NAME=CleanLauncher.apk

die() { echo "error: $*" >&2; exit 1; }

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) WIN=1; EXE=.exe; BAT=.bat ;;
    *)                    WIN=0; EXE=;     BAT=     ;;
esac

SDK=${ANDROID_HOME:-$ANDROID_SDK_ROOT}
if [ -z "$SDK" ]; then
    for d in "$LOCALAPPDATA/Android/Sdk" "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
        [ -d "$d" ] && SDK=$d && break
    done
fi
[ -n "$SDK" ] && [ -d "$SDK" ] || die "Android SDK not found."
[ "$WIN" = 1 ] && command -v cygpath >/dev/null && SDK=$(cygpath -u "$SDK")

PLATFORM=${ANDROID_PLATFORM:-android-33}
JAR=$SDK/platforms/$PLATFORM/android.jar
[ -f "$JAR" ] || die "missing $PLATFORM."

if [ -z "$BUILD_TOOLS" ]; then
    BUILD_TOOLS=$(ls "$SDK/build-tools" 2>/dev/null | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)
fi
BT=$SDK/build-tools/$BUILD_TOOLS

if [ -n "$JAVA_HOME" ]; then
    JDK=$JAVA_HOME/bin
elif command -v javac >/dev/null 2>&1; then
    JDK=$(dirname "$(command -v javac)")
fi
export JAVA_HOME="${JDK%/bin}"

KEYSTORE=${KEYSTORE:-$HOME/.android/debug.keystore}
KEYSTORE_PASS=${KEYSTORE_PASS:-android}
KEY_ALIAS=${KEY_ALIAS:-androiddebugkey}
if [ ! -f "$KEYSTORE" ]; then
    mkdir -p "$(dirname "$KEYSTORE")"
    "$JDK/keytool$EXE" -genkeypair -keystore "$KEYSTORE" -storepass "$KEYSTORE_PASS" \
        -keypass "$KEYSTORE_PASS" -alias "$KEY_ALIAS" -keyalg RSA -keysize 2048 -validity 10000 \
        -dname "CN=Android Debug,O=Android,C=US"
fi

# --- PERSONALIZACIÓN AUTOMÁTICA PARA BREYNER ---
# 1. Cambia JHON / Jhon por Breyner en todo el código y diseño
find src res -type f \( -name "*.java" -o -name "*.xml" \) -exec sed -i 's/JHON/Breyner/g; s/Jhon/Breyner/g' {} +

# 2. Elimina los audios grabados con la voz de Jhon para que lea Breyner
rm -f res/raw/v_*.mp3
rmdir res/raw 2>/dev/null || true
# -----------------------------------------------

rm -rf build && mkdir -p build/gen build/classes build/dex

RES=res
if [ "$VARIANT" = share ]; then
    RES=build/res-share
    cp -r res "$RES"
    rm -f "$RES"/drawable-nodpi/optra*.png "$RES"/raw/v_*.mp3
    rmdir "$RES"/raw "$RES"/drawable-nodpi 2>/dev/null || true
    APK_NAME=CleanLauncher-compartir.apk
fi

"$BT/aapt2$EXE" compile --dir "$RES" -o build/res.zip
"$BT/aapt2$EXE" link -I "$JAR" --manifest AndroidManifest.xml \
    --min-sdk-version $MIN_SDK --target-sdk-version $TARGET_SDK \
    --java build/gen -o build/unsigned.apk build/res.zip

"$JDK/javac$EXE" -nowarn -Xlint:-options --release 8 -encoding UTF-8 \
    -classpath "$JAR" -d build/classes \
    $(find src build/gen -name '*.java')

"$BT/d8$BAT" --min-api $MIN_SDK --lib "$JAR" --output build/dex $(find build/classes -name '*.class')

(cd build/dex && "$JDK/jar$EXE" uf ../unsigned.apk classes.dex)
"$BT/zipalign$EXE" -f 4 build/unsigned.apk build/aligned.apk
"$BT/apksigner$BAT" sign --ks "$KEYSTORE" --ks-pass "pass:$KEYSTORE_PASS" --ks-key-alias "$KEY_ALIAS" \
    --out "build/$APK_NAME" build/aligned.apk

echo "APK: build/$APK_NAME"
