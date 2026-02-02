# S.INC | Procrastinator 

<p align="center">
  <a href="https://github.com/smithinkr/sinc-procrastinator/releases/latest">
    <img src="https://img.shields.io/badge/Download-S.Inc%20Procrastinator-2bbdb3?style=for-the-badge&logo=android&logoColor=white" />
  </a>
</p>

<p align="center">
  <i>"Precision Task Management for the Forgetful Professional"</i>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/smithinkr/sinc-procrastinator/main/assets/banner%20background%20light.png" width="100%" alt="S.INC Banner" />
</p>

---

## 🏛 The Narrative: Why Procrastinator?
Most task apps are built for people who already have it together. I am a self-described **forgetful person** who found existing market solutions too rigid, too complex, or lacking in proactive intelligence. 

I didn't just want a list; I wanted a partner. **Procrastinator** was born from that gap. It is a flagship engine developed with the analytical rigor of a **Lead Business Analyst** and the creative flexibility of "Vibe Coding." It identifies the friction points of modern productivity and solves them with AI-driven automation.

## 📸 Interface Preview
<p align="center">
  <img src="https://raw.githubusercontent.com/smithinkr/sinc-procrastinator/main/assets/1.homescreen.png" width="32%" alt="Home Screen" />
  </p>

## 🚀 Core Features
* **Smart HUD (Today at a Glance):** A high-visibility, transparent overlay that keeps your immediate priorities front and center. Includes gesture pass-through logic for seamless navigation.
* **Server-Side AI Intelligence:** Native integration with **Firebase Vertex AI**. This allows for natural language parsing and automatic subtask generation without exposing client-side API keys.
* **Cloud-Sync & Persistence:** Real-time Firebase integration allowing seamless transitions between mobile devices (Optimized for OnePlus 12 and Samsung S23 FE).
* **Enterprise Security Architecture:** Hardened APK build utilizing **Digital Asset Links** for domain verification and Firebase Security Rules to protect user data.
* **Adaptive Theme Engine:** A Glassmorphic UI that reacts to device light/dark mode settings and custom S.INC color palettes.

## 🛠 Technical Architecture
* **Framework:** Flutter (Material 3)
* **Backend:** Firebase Auth & Firestore
* **AI Integration:** Firebase Vertex AI (Gemini 1.5 Flash)
* **Security:** SHA-256 Signing, ProGuard/R8 Obfuscation, and Firebase App Check.
* **State Management:** Provider for real-time UI synchronization.

## 📥 Installation & Onboarding
To run this production-hardened build locally, follow the S.INC protocol:

1.  **Clone the Repository:**
    ```bash
    git clone [https://github.com/smithinkr/sinc-procrastinator.git](https://github.com/smithinkr/sinc-procrastinator.git)
    ```
2.  **Firebase Configuration:**
    Because this app uses a secure Firebase-side AI implementation, you must provide your own `google-services.json` file in `android/app/`.
3.  **Reconcile Dependencies:**
    ```bash
    flutter pub get
    ```
4.  **Production Hardening (Obfuscated Build):**
    ```bash
    flutter build apk --release --obfuscate --split-debug-info=build/app/outputs/symbols
    ```

## 💼 Business Analyst & Implementation Focus
This project demonstrates a "Full-Cycle" product mindset:
1.  **Requirement Translation:** Converting the "pain point" of forgetfulness into a structured technical requirement set.
2.  **Security Governance:** Implementing **Digital Asset Links** and server-side AI calls to mitigate credential leaks—ensuring production-ready safety.
3.  **Deployment Excellence:** Managing the pivot from a third-party marketplace to a secure, verified GitHub distribution pipeline.
4.  **Version Control Mastery:** Maintaining a clean, secure, and documented ledger via Git.

---

© 2026 S.INC | Developed by [Smithin K R]