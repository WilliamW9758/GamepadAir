# Layered app icons

Controller.svg recreates the existing Pocket Pad silhouette as an even-odd vector path with transparent control cutouts. The user explicitly approved vector reconstruction. The three .icon packages are native Icon Composer documents; their shared foreground preserves the original proportions.

Use the PhoneGamepad Xcode target to compile these icons and retain native dark, clear and tinted appearances. The primary iOS name is PocketPad; alternate names stay AppIconWhite and AppIconGraphite for compatibility with saved selections. The Mac retains its existing AppIcon asset catalog.

IconPreviewRed/White/Graphite.png were exported from Icon Composer at 1024pt, Default appearance; copies are in the corresponding image sets for the in-app picker. Re-export after editing the icon documents. The old flat alternate sources are retained under Assets/LegacyAppIcons for the explicitly legacy SDK-only install script.
