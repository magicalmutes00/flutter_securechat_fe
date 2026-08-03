# SecureChat — Flutter Client

SecureChat is a WhatsApp-style secure chat application. This repository holds the
Flutter client; the Dart backend lives in `flutter_securechat_bk/`.

## Features

- OTP + email/phone-password onboarding with JWT sessions
- Privacy-preserving contacts sync (SHA-256 phone hashes)
- End-to-end encryption via Signal protocol (`libsignal_protocol_dart`), including
  group messages with sender keys and encrypted media (AES-GCM + Signal envelope)
- Read/delivered receipts, typing indicators, offline message queue, search
- Group chats (create, manage members, group E2EE sender keys)
- WebRTC voice/video calls with STUN/TURN
- Status stories (text/image, 24-hour expiry, viewer tracking)
- At-rest encryption for local caches (AES-256, key in secure storage)

## Getting Started

1. `flutter pub get`
2. Point the client at a running backend:
   ```sh
   flutter run --dart-define=API_BASE_URL=http://localhost:8080
   ```
   Override `WS_PATH=/ws` when the socket path differs.

## Configuration

All environment-overridable configuration lives in
`lib/core/environment/environment_config.dart`.

## Testing

```sh
flutter test
```
