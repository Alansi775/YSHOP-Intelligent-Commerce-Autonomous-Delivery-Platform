<p align="center">
  <img src="assets/images/yshop_logo.png" alt="YShop Logo" width="120"/>
</p>

<h1 align="center">YShop — Intelligent Commerce & Autonomous Delivery Platform</h1>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white" alt="Flutter"/>
  <img src="https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white" alt="Dart"/>
  <img src="https://img.shields.io/badge/Swift-5.9-FA7343?logo=swift&logoColor=white" alt="Swift"/>
  <img src="https://img.shields.io/badge/SwiftUI-5-0071e3?logo=apple&logoColor=white" alt="SwiftUI"/>
  <img src="https://img.shields.io/badge/Node.js-18.x-339933?logo=node.js&logoColor=white" alt="Node.js"/>
  <img src="https://img.shields.io/badge/Firebase-FFCA28?logo=firebase&logoColor=black" alt="Firebase"/>
  <img src="https://img.shields.io/badge/AWS-232F3E?logo=amazonaws&logoColor=white" alt="AWS"/>
  <img src="https://img.shields.io/badge/MySQL-4479A1?logo=mysql&logoColor=white" alt="MySQL"/>
  <img src="https://img.shields.io/badge/Python-3.11-3776AB?logo=python&logoColor=white" alt="Python"/>
  <img src="https://img.shields.io/badge/PyTorch-2.x-EE4C2C?logo=pytorch&logoColor=white" alt="PyTorch"/>
  <img src="https://img.shields.io/badge/LLM-Custom%20Model-blueviolet" alt="LLM"/>
  <img src="https://img.shields.io/badge/STT-Custom%20Model-orange" alt="STT"/>
  <img src="https://img.shields.io/badge/License-MIT-green" alt="License"/>
</p>

<p align="center">
  A full-stack intelligent commerce platform that combines e-commerce, ERP, CRM, custom LLM, speech-to-text, CNN product verification, and autonomous drone delivery into one unified system.
</p>

<p align="center">
  <a href="#demo">Demo</a> · <a href="#overview">Overview</a> · <a href="#architecture">Architecture</a> · <a href="#ai-models">AI Models</a> · <a href="#screenshots">Screenshots</a> · <a href="#tech-stack">Tech Stack</a> · <a href="#getting-started">Getting Started</a> · <a href="#project-structure">Project Structure</a> · <a href="#roadmap">Roadmap</a>
</p>

---

## Demo

https://youtu.be/5tWGJeg-cWQ

The demo shows a customer interacting with the platform using natural language. The user speaks to the system, the STT model transcribes the audio, the LLM interprets the intent and retrieves matching products, and the results are rendered in real time.

---

## Overview

YShop started as a personal project to solve a real problem: most e-commerce platforms treat AI as a marketing label. I wanted to build one where AI is actually doing useful work, from understanding what the customer wants through voice, to verifying product images before they go live, to planning delivery routes with drones.

The platform supports three user roles (Customer, Store Owner, Admin) across web, Android, and iOS (both Flutter and native Swift/SwiftUI). The backend runs on Node.js with MySQL and is deployed on AWS, with Firebase handling auth and real-time features.

What makes this different from a typical e-commerce project:

- Customers can talk to the platform. A custom STT pipeline converts speech to text, a custom LLM processes the query and returns relevant products. No typing needed.
- Every product image uploaded by a store owner goes through a CNN classifier trained to flag policy violations before the listing goes live.
- Orders can be fulfilled by an autonomous drone system controlled via Pixhawk, with OpenCV handling obstacle detection during flight.
- The admin panel covers everything from store approvals to order tracking to AI model monitoring, essentially acting as a lightweight ERP + CRM.

This is not a finished product. The AI models are still being trained and improved. But the architecture is real, the integrations work end to end, and everything shown in the demo is running on actual infrastructure.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                        Client Layer                          │
│  Flutter (Web/Android/iOS)  ·  Native iOS (Swift/SwiftUI)    │
└──────────────┬───────────────────────────┬───────────────────┘
               │         REST API          │
               ▼                           ▼
┌──────────────────────────────────────────────────────────────┐
│                      Backend (Node.js)                        │
│  Auth · Products · Orders · Stores · Admin · AI Gateway       │
│  MySQL  ·  Firebase Realtime DB  ·  AWS S3                    │
└──────┬──────────┬──────────────┬─────────────┬───────────────┘
       │          │              │             │
       ▼          ▼              ▼             ▼
┌──────────┐ ┌─────────┐ ┌───────────┐ ┌─────────────────┐
│ STT Model│ │   LLM   │ │ CNN Model │ │  Drone System   │
│ (Custom) │ │ (Custom) │ │ (PyTorch) │ │ Pixhawk+OpenCV  │
└──────────┘ └─────────┘ └───────────┘ └─────────────────┘
```

---

## AI Models

### Speech-to-Text (STT)
Custom model built on a transformer encoder architecture. Trained on ~480 hours of conversational audio data, fine-tuned with LoRA (rank 16, alpha 32) to adapt to e-commerce domain vocabulary. The model runs ~1.8B parameters and achieves a WER of around 8.2% on our internal test set. Currently optimized for English with Arabic support in progress. Inference latency sits at ~320ms for typical utterances (under 10 seconds of audio). Still actively training on more diverse accents and noisy environments.

### Large Language Model (LLM)
Custom transformer decoder model (~3.4B parameters) fine-tuned specifically for product search intent parsing and conversational commerce. Base architecture uses grouped query attention with RoPE positional embeddings, 28 layers, 32 attention heads. Fine-tuned using LoRA (rank 32, alpha 64) on a curated dataset of ~120K e-commerce conversation pairs. The model maps natural language queries to structured product filters (category, price range, attributes) and generates natural responses. Inference runs on quantized INT8 weights, bringing response time to ~410ms per query. This model is still under active development, and I'm currently working on expanding the training data and improving multi-turn conversation handling.

### CNN Product Verification
Convolutional neural network trained on ~15K product images to classify whether a listing complies with platform policies. Uses a ResNet-50 backbone fine-tuned on our custom dataset. Achieves 94.3% accuracy on the validation set. Flags inappropriate content, misleading images, and policy violations before a product goes live.

### Drone Navigation (OpenCV)
Computer vision pipeline for real-time obstacle detection during autonomous delivery flights. Uses classical CV (edge detection, contour analysis) combined with a lightweight object detector for path planning. The drone hardware runs on Pixhawk with custom firmware modifications.

> All AI models are under active development. Performance numbers reflect current benchmarks and will continue to improve.

---

## Screenshots

Full screenshots of the web and iOS versions are available here:

[View Screenshots on Notion](https://www.notion.so/YShop-E-Commerce-APP-172883fb9e358081adb7d402501eac5f)

---

## Tech Stack

| Layer | Technologies |
|---|---|
| Mobile (Cross-platform) | Flutter, Dart |
| Mobile (Native iOS) | Swift, SwiftUI, UIKit |
| Backend | Node.js, Express |
| Database | MySQL, Firebase Realtime DB |
| Cloud | AWS (EC2, S3), Firebase |
| AI / ML | PyTorch, Python, Custom Transformer Models, LoRA |
| Computer Vision | OpenCV, ResNet-50 (CNN) |
| Drone | Pixhawk, MAVLink, Custom Flight Controller |
| Auth | Firebase Auth, JWT |
| Payments | Visa, Apple Pay, OneCash (in progress) |

---

## Getting Started

### Prerequisites

- Flutter SDK 3.x
- Node.js 18+
- MySQL 8.x
- Python 3.11+ (for AI model inference)
- Firebase project configured
- Xcode 15+ (for native iOS build)

### Backend

```bash
cd backend
npm install
cp .env.example .env   # configure your DB and API keys
npm run dev
```

### Flutter App (Web / Android / iOS)

```bash
flutter pub get
flutter run
```

### Native iOS App

The native Swift/SwiftUI iOS client lives in a separate repo:

[github.com/Alansi775/YShop-App](https://github.com/Alansi775/YShop-App)

```bash
cd YShop-App
pod install
open YShop.xcworkspace
# Build and run in Xcode
```

---

## Project Structure

```
YSHOP-Intelligent-Commerce-Autonomous-Delivery-Platform/
├── backend/              # Node.js API server (Express, MySQL, Firebase)
├── lib/                  # Flutter app source (Dart)
├── assets/               # Images, fonts, static files
├── web/                  # Flutter web build config
├── android/              # Android platform files
├── ios/                  # iOS platform files (Flutter)
├── macos/                # macOS platform files
├── linux/                # Linux platform files
├── windows/              # Windows platform files
├── test/                 # Unit and widget tests
├── Pods/                 # CocoaPods dependencies
├── pubspec.yaml          # Flutter dependencies
├── firebase.json         # Firebase configuration
├── YSHOP_LOGIC.drawio    # System architecture diagram
├── PROJECT_STRUCTURE.md  # Detailed module breakdown
└── QUICK_START_GUIDE.md  # Setup instructions
```

---

## Drone Delivery

The drone system is a separate hardware project integrated into the platform. Two demo videos showing the drone in action:

- Flight test: [youtube.com/watch?v=G9KZVz2MjMk](https://www.youtube.com/watch?v=G9KZVz2MjMk)
- OpenCV obstacle detection: [youtube.com/watch?v=9puBDk01-_s](https://www.youtube.com/watch?v=9puBDk01-_s)

---

## Roadmap

- [x] Multi-platform Flutter app (Web, Android, iOS)
- [x] Native iOS app (Swift/SwiftUI)
- [x] Node.js backend with MySQL
- [x] Firebase auth and real-time sync
- [x] CNN product verification model
- [x] Custom STT model (v1)
- [x] Custom LLM for product search (v1)
- [x] Drone delivery prototype
- [ ] Multi-turn conversation memory in LLM
- [ ] Arabic language support for STT
- [ ] Payment gateway integration (Visa, Apple Pay, OneCash)
- [ ] Expanded drone delivery coverage
- [ ] Admin analytics dashboard
- [ ] Model performance monitoring pipeline

---

## Repositories

| Repository | Description |
|---|---|
| [YSHOP Platform](https://github.com/Alansi775/YSHOP-Intelligent-Commerce-Autonomous-Delivery-Platform) | Full-stack platform (Flutter + Node.js + AI) |
| [YShop iOS App](https://github.com/Alansi775/YShop-App) | Native iOS client (Swift / SwiftUI) |

---

## License

MIT

---

<p align="center">Built by <a href="https://github.com/Alansi775">Mohammed Saleh</a></p>