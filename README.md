# S.INC | Procrastinator 

<p align="center">
  <a href="https://github.com/smithinkr/sinc-procrastinator/releases/latest">
    <img src="https://img.shields.io/badge/Download-S.Inc%20Procrastinator-2bbdb3?style=for-the-badge&logo=android&logoColor=white" />
  </a>
</p>

> Precision Task Management for the Forgetful Professional

[S.INC Branding] [Build-Status] [Platform: Android/OnePlus/Samsung]

---

## 🏛 The Narrative: Why Procrastinator?
Most task apps are built for people who already have it together. I am a self-described **forgetful person** who found existing market solutions too rigid, too complex, or lacking in proactive intelligence. 

I didn't just want a list; I wanted a partner. **Procrastinator** was born from that gap. It is a flagship engine developed with the analytical rigor of a **Lead Business Analyst** and the creative flexibility of "Vibe Coding." It identifies the friction points of modern productivity and solves them with AI-driven automation.

## 🚀 Core Features
* **Smart HUD (Today at a Glance):** A high-visibility, transparent overlay that keeps your immediate priorities front and center without cluttering the UI. Includes gesture pass-through logic for seamless navigation.
* **Gemini AI Intelligence:** Native integration with Google Gemini for natural language parsing, automatic subtask generation, and "sassy" morning briefings.
* **Cloud-Sync & Persistence:** Real-time Firebase integration allowing seamless transitions between mobile devices (Optimized for OnePlus 12 and Samsung S23 FE).
* **Production-Grade Security:** Hardened APK build with full code obfuscation and hardware-backed secret vaulting to protect API credentials.
* **Adaptive Theme Engine:** Glassmorphic UI that reacts to your device's light/dark mode settings and custom S.INC color palettes.

## 🛠 Technical Architecture
* **Framework:** Flutter (Material 3)
* **Backend:** Firebase Auth & Firestore
* **AI Engine:** Google Gemini AI (Vertex AI/AI Studio)
* **Security:** AES-GCM Encryption, Envied (Obfuscation), and Hardware-backed Storage.
* **State Management:** Provider for real-time UI synchronization.


## 📥 Installation & Setup
To run this production-hardened build locally, follow the S.INC onboarding protocol:

1.  **Clone the Repository:**
    ```bash
    git clone [https://github.com/smithinkr/sinc-procrastinator.git](https://github.com/smithinkr/sinc-procrastinator.git)
    ```
2.  **Reconcile Dependencies:**
    ```bash
    flutter pub get
    ```
3.  **Environment Configuration:**
    Create a `.env` file in the root directory and add your Gemini API Key:
    ```text
    GEMINI_API_KEY=your_key_here
    ```
4.  **Run Development Build:**
    ```bash
    flutter run
    ```
5.  **Production Hardening (Obfuscated Build):**
    ```bash
    flutter build apk --release --obfuscate --split-debug-info=build/app/outputs/symbols
    ```

## 📈 Project Roadmap: Future Iterations
* [ ] **WearOS Integration:** Bringing the HUD to the wrist for even faster "at-a-glance" access.
* [ ] **S.INC Collaboration:** Shared task lists with real-time AI conflict resolution.
* [ ] **Voice-First HUD:** Total hands-free task creation using advanced audio recording logic.

## 💼 Business Analyst & Implementation Focus
This project serves as a live demonstration of my ability to:
1.  **Translate User Needs:** Converting personal forgetfulness into a structured requirement set.
2.  **Architect Solutions:** Designing a secure, scalable cloud-to-mobile infrastructure.
3.  **Execute Deployment:** Hardening the application for production use on high-end Android hardware.
4.  **Version Control Mastery:** Maintaining a clean, secure, and documented GitHub ledger.

---

## 📜 License
This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

© 2026 S.INC | Developed by [Your Name]
