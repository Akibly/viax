# ViaX blue icon refresh

Updated `mobile/assets/viax_icon.png` and `mobile/assets/viax_mark.png` with the built-in image editor. The main edit prompt was: replace the dark green background with cobalt blue #3157D5, preserving the white X silhouette, coral arrow, scale and margins. The foreground prompt requested a transparent, centered white/coral mark without green fringe.

Regenerated browser favicon, web install icons, and Android launcher resources with `dart run flutter_launcher_icons`. Android adaptive background now uses #3157D5. Website canvas and browser theme retain the existing paper/deep-ink tokens.

The Android source assets are updated; this pass does not rebuild or distribute an APK.
