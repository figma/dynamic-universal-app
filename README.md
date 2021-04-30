## Dynamic Universal App

Dynamic Universal App (DUA) is tiny bootstrap app that simplifies the user
download process for macOS applications with Intel and Apple Silicon builds.
It is an bandwidth efficient alternative to [universal fat binaries](https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary).

Users download the DUA bundle (customized with the real app name and icon)
instead of the real app. On launch, it will automatically download the
architecture specific build of your app, replace itself with the real app, and
finally switch over to the real app.

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
