# SmartStock Pro Android

Flutter MVP shell. For local Android platform scaffolding, run:

```bash
cd mobile
flutter create --platforms=android .
flutter pub get
flutter run
```

Android emulator reaches a backend on the host machine through `http://10.0.2.2:8000`. Change Backend URL in the app for a physical device or deployed server.

This first screen checks backend health and loads the imported stock-symbol universe. It intentionally does not display fabricated quotes.
