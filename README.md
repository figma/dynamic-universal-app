## Dynamic Universal App

Dynamic Universal App (DUA) is tiny bootstrap app that simplifies the user
download process for macOS applications with Intel and Apple Silicon builds.
It is an bandwidth efficient alternative to [universal fat binaries](https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary).

Users download the DUA bundle (customized with the real app name and icon)
instead of the real app. On launch, it will automatically download the
architecture specific build of your app, replace itself with the real app, and
finally switch over to the real app.

<img width="512" alt="figma-dua" src="https://user-images.githubusercontent.com/1319028/116702718-1bd37000-a9d2-11eb-9f36-bf7ede60de1b.png">

Compared to normal universal binaries or listing architecture specific
download links, this has the following benefits:

* Simpler download page for your users. They won't have to know what "Intel" or
  "Apple Silicon" means.

* Faster downloads. Normal universal binaries can make your app up to 2x
  larger.

* In the future, even faster downloads with XZ compression. Traditionally
  macOS apps are distributed as ZIPs or DMGs, but they offer subpar
  compression ratios. DUA will optionally able to download the real app from
  an XZ package to reduce download time even further. For basic Electron apps,
  XZ reduces the download from 80MB to 60MB.

### Notes

DUA will not work for enterprise deployments where the end-users do not have
write access to `/Applications`. You will likely want to provide direct links
to architecture-specfic builds somewheree for use by enterprise admins.

### Packaging

This needs to be automated, but here are manual steps:

```sh
xcodebuild -project DynamicUniversalApp.xcodeproj -configuration Release

APP_DIR="build/Release/DynamicUniversalApp.app"
INFO_PLIST="$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'set CFBundleIdentifier com.figma.desktop.dynamic-universal-app' "$INFO_PLIST"
/usr/libexec/PlistBuddy -c 'set TargetAppName Figma' "$INFO_PLIST"
/usr/libexec/PlistBuddy -c 'set TargetDownloadURLs:aarch64 https://desktop.figma.com/mac-arm/Figma.zip' "$INFO_PLIST"
/usr/libexec/PlistBuddy -c 'set TargetDownloadURLs:x86_64 https://desktop.figma.com/mac/Figma.zip' "$INFO_PLIST"

/usr/libexec/PlistBuddy -c 'add CFBundleIconFile string icon.icns' "$INFO_PLIST"
cp /path/to/icon.icns "$APP_DIR/Contents/Resources/icon.icns"

mv DynamicUniversalApp.app Figma.app

codesign --force --options=runtime --timestamp --sign "Developer ID Application: ..." Figma.app
cd ~/figma/figma/desktop
node scripts/notarize.js com.figma.desktop.dynamic-universal-app "$APP_DIR"
```
