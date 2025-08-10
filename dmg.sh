APP_DIR="build/DerivedData/Build/Products/Release"
APP_NAME="ZMKBatteryUtil.app"         
VOL_NAME="ZMKBatteryUtil"            

rm -rf dist dmgroot
mkdir -p dist dmgroot
cp -R "$APP_DIR/$APP_NAME" dmgroot/

REAL_CD=$(realpath "$(command -v create-dmg)")
"$REAL_CD" --volname "ZMKBatteryUtil" --window-size 600 400 --app-drop-link 450 200 dist/ZMKBatteryUtil.dmg "dmgroot"

