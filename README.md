# inkscape_app

A Flutter app to try tattoos on your photos.

## Pinterest Tattoo Selection

- Tap `TATTOO` to open the in‑app Pinterest browser. Open a pin and tap “Bu dövmeyi kullan”.
- Or simply tap the photo area to open the in-app web browser and pick a tattoo from Pinterest; choose a pin and tap “Bu dövmeyi kullan”.
- The app receives the shared image (Android via Share Intent; iOS via Share Extension) and overlays it on your photo.
- If a Pinterest link is shared instead of a file, the app will resolve the image via Open Graph/Twitter meta tags.

### iOS Setup

- Project includes a Share Extension. In Xcode set a valid App Group for both Runner and Share Extension targets:
  - Build Settings → `CUSTOM_GROUP_ID` → e.g. `group.com.yourcompany.inkscape`
  - Ensure the same App Group is enabled in both targets’ Signing & Capabilities.

### Android Setup

- AndroidManifest already declares `SEND`/`SEND_MULTIPLE` intent-filters for `image/*` and `text/plain` and INTERNET permission.
