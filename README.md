# Lacuna

A premium iOS time capsule app. Seal a thought, a photo, or a voice note — for your future self or someone you love. No peeking. No extending. That is the point.

## Features

- **Text capsules** — WYSIWYG editor with bold, italic, and paragraph formatting (New York serif)
- **Writing prompts** — a library of literary, reflective prompts surfaced in the editor when words don't come
- **Letter to tomorrow** — one-tap quick capture from the home screen that opens 24 hours later
- **Photo capsules** — from library or camera, with smart compression
- **Voice capsules** — record voice notes with animated waveform playback
- **Send via iMessage** — recipient taps the rich card and the capsule imports straight into Lacuna, no file dance. Media is end-to-end encrypted in transit
- **Send via any other app** — AirDrop, WhatsApp, email, Files — falls back to a portable `.capsule` file
- **Reveal ceremony** — multi-phase animation with haptics and synthesized audio when a capsule opens
- **Local-first** — we operate no servers. Capsules live on your device and sync via your own iCloud
- **Lacuna +** — one-time purchase for unlimited capsules, camera access, and sending

## Tech Stack

- SwiftUI + SwiftData, with CloudKit private DB for personal sync and a public-DB transport for end-to-end-encrypted iMessage media
- iOS 26+, Swift 6.0 (strict concurrency)
- RevenueCat for in-app purchases
- AVFoundation for audio recording/playback and synthesized reveal tones
- CryptoKit (AES-GCM) for capsule encryption in the iMessage transport
- No third-party UI frameworks

## Architecture

```
embargo/           — main app
  Models/          — Capsule (SwiftData), CapsuleType, CapsulePackage, CreateStep, AppearanceMode
  Views/           — Home, Create flow, Sealed, Opened, Reveal, Settings, Archive, Onboarding, Paywall
  Components/      — FloatingParticles, TextEditor, PhotoEditor, AudioControls, RevealCeremony
  Utilities/       — StoreManager, AudioManager, NotificationManager, Design system,
                     CapsuleExporter/Importer, iMessageSender, CapsuleTransport, MessagesAppGroup
embargoMessages/   — iMessage extension (MSMessagesAppViewController) — renders rich capsule
                     cards in iMessage and hands off to the main app via App Group + URL scheme
```

## Design

Cream-and-black aesthetic. All text lowercase. All corners angular (0 radius). Wide letter-spacing. Geometric floating particles with comets. Haptic feedback on every interaction.

## License

All rights reserved. This is a commercial app.

## Author

Antonio Baltic — [antoniobaltic@icloud.com](mailto:antoniobaltic@icloud.com)
