# 🛡️ Shield Guard — DNS Firewall & VPN for Flutter

[![Flutter](https://img.shields.io/badge/Flutter-2.0-blue)](https://flutter.dev)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

---

## About

Shield Guard is a powerful Flutter-based VPN & DNS firewall app that protects your privacy by blocking unwanted domains, supporting encrypted DNS protocols (DoH, DoT, etc.), and offering easy management of DNS providers.

---

## Features

- Select and switch between popular DNS providers
- Support for multiple DNS query methods: UDP, TCP, DoH (HTTPS), DoT (TLS)
- Block unwanted domains with a customizable denylist
- Real-time VPN start/stop controls with status indicators
- Dark-themed clean UI built with Flutter

---

## Screenshots

![Home Screen](screenshots/home_screen.png)
![Provider Selection](screenshots/provider_selection.png)

---

## Getting Started

### Prerequisites

- Flutter SDK installed (>=2.0)
- Android Studio / Xcode for platform builds
- Android device/emulator with VPN support

### Installation

```bash
git clone https://github.com/MohammedAbdulwahab3/flutter_firewall.git
cd flutter_firewall
flutter pub get
flutter run
