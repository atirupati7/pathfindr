# PathFindr

**PathFindr** is an iOS application designed to help people who are visually impaired navigate their surroundings using ARKit, LiDAR depth sensing, and a multimodal AI backend powered by Google’s Gemini models. The app provides real-time obstacle detection, spatial audio guidance, haptic feedback, and intelligent conversational assistance—all through a natural, voice-driven interface.

---

## Features

### Core Navigation

* **AR-Based Navigation:** Uses Apple’s ARKit and LiDAR sensors to construct a real-time 3D map of the surroundings.
* **Real-Time Depth Sensing:** Continuously calculates object distances and spatial relationships.
* **Obstacle Detection:** Identifies and classifies objects as potential hazards.
* **Spatial Audio Guidance:** Provides directional audio cues to indicate nearby obstacles.
* **Haptic Feedback:** Vibrations alert users when they approach nearby objects.

### AI-Powered Assistance

* **Gemini-Powered Multi-Agent Backend:** Integrates five specialized Gemini agents (Prompt, Hazard Detector, Image, Semantic, and Narrator) via a Flask middleware.
* **Adaptive Descriptions:** The system fuses spatial and semantic insights to describe scenes contextually.
* **Prompt vs. No-Prompt Modes:**

  * *No Prompt Mode:* Automatically guides the user through live navigation.
  * *Prompt Mode:* Responds to user-initiated questions with contextual awareness.
* **Conversation Memory:** Uses Firebase to store previous exchanges, allowing follow-up questions with retained context.
* **OCR Support:** Reads and describes printed text in the environment (e.g., signs, menus).

### Voice Interaction

* **Hold-to-Speak Button:** Users can press and hold to ask questions about their surroundings.
* **Speech Recognition:** Transcribes input using Apple’s Speech framework.
* **Text-to-Speech Output:** Converts AI responses and navigation descriptions into natural audio.
* **Smart Interruptions:** Automatically pauses streaming descriptions when the user is speaking.

### User Experience

* **Full-Screen Camera View:** Displays a live camera feed with unobtrusive UI.
* **Movement Detection:** Announces obstacles only when the user is moving.
* **Distance Announcements:** Includes distance values in object descriptions.
* **Visual Feedback:** Provides real-time transcription and recording indicators.

---

## How We Built It

PathFindr is built around a **multimodal AI architecture** that merges **on-device sensing** with a **Gemini-powered multi-agent backend**.

1. **Frontend (iOS, Swift + ARKit):**

   * Captures LiDAR and RGB camera data.
   * Constructs a 3D environmental model and extracts object positions and depth information.
   * Sends structured JSON payloads to the Flask backend.

2. **Middleware (Flask):**

   * Receives HTTP POST requests from the app.
   * Forwards the processed JSON data to the **Agent Development Kit (ADK)** backend.

3. **Backend (ADK with Gemini):**

   * Coordinates multiple Gemini agents:

     * **Prompt Agent** – interprets user prompts and orchestrates other agents.
     * **Hazard Detector Agent** – evaluates object proximity and risk.
     * **Image Agent** – performs advanced scene understanding.
     * **Semantic Agent** – generates descriptive, context-aware language.
     * **Narrator Agent** – compiles outputs into a concise, natural-language summary.
   * Returns a unified text output for speech playback on the device.

4. **Data Flow Summary:**

   ```
   LiDAR + Camera Data → Swift (ARKit) → Flask Middleware → Gemini ADK → Audio Output
   ```

## What’s Next for PathFindr

The next step for PathFindr is full **end-to-end navigation** — guiding users from their current position to a specified destination using **GPS integration**. Future updates will also:

* Incorporate **Google Maps APIs** for outdoor navigation.
* Extend **Gemini memory** for persistent user profiles.
* Optimize **energy efficiency** and reduce latency for continuous operation.
* Explore **edge-based inference** for improved privacy and offline support.

---

## Requirements

* **iOS 18.6 or later**
* **iPhone 12 Pro or later** (LiDAR required)
* **Google Gemini API key**
* **Firebase project** (for conversation memory)
* **Xcode 15.0 or later**

---

## Setup

### 1. Clone the Repository

```bash
git clone https://github.com/atirupati7/pathfindr.git
cd pathfindr
```

### 2. Install Dependencies

The project uses Swift Package Manager for Firebase dependencies:

1. Open `PathFindr.xcodeproj` in Xcode
2. Go to **File > Add Package Dependencies**
3. Add: `https://github.com/firebase/firebase-ios-sdk`
4. Select **FirebaseCore** and **FirebaseFirestore**, then click *Add Package*

### 3. Configure API Keys

Copy:

```
PathFindr/System/APIKeys.example.swift → PathFindr/System/APIKeys.swift
```

Edit the file to include your Gemini API key:

```swift
static let geminiAPIKey = "YOUR_GEMINI_API_KEY_HERE"
```

### 4. Configure Firebase

1. Create a Firebase project in the [Firebase Console](https://firebase.google.com/).
2. Add an iOS app with bundle ID: `com.atirupati07.pathfindr`
3. Download `GoogleService-Info.plist` and place it in `PathFindr/`
4. Enable **Firestore Database** and set up basic test rules:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /conversations/{userId}/exchanges/{exchangeId} {
      allow read, write: if request.time < timestamp.date(2024, 12, 31);
    }
  }
}
```

### 5. Build and Run

* Open the project in Xcode
* Select your development team
* Connect your iPhone (with LiDAR)
* Build and run using **Cmd + R**

---

## Usage

### Starting Navigation

1. Launch the app and grant camera, microphone, and motion permissions.
2. Tap **Start Guidance**.
3. The app will describe your surroundings using spatial audio and haptic feedback.

### Asking Questions

1. Press and hold the **blue microphone button**.
2. Ask a question (e.g., *“What’s in front of me?”* or *“How far is the wall?”*).
3. Release to send; the app will respond through audio.

### Dual Modes

* **Streaming Mode:** Continuous navigation with live descriptions.
* **Prompt Mode:** Stops streaming to process and answer user queries.

---

## Troubleshooting

**App Icon Not Showing**

* Delete the app and clean the Xcode build folder (`Cmd+Shift+K`) before rebuilding.

**Firebase Not Working**

* Ensure `GoogleService-Info.plist` is correctly added and included in build targets.

**Voice Input Issues**

* Grant microphone and speech recognition permissions.
* Verify the hold button changes color when pressed.

**Low Audio Output**

* Check device volume settings; the app outputs at max audio level.

---

## Development

### Building for Device

* Use a real iPhone with LiDAR support.
* Select your Apple Developer Team in Xcode.
* Build and run directly (Cmd+R).

### Testing

* Test in quiet environments to ensure accurate speech detection.
* Validate Firestore storage for conversation history.

---

## License

This project was developed as part of a hackathon submission.

---

## Acknowledgments

* **Google Gemini API** – Multimodal vision and language understanding
* **Apple ARKit** – Real-time spatial mapping
* **Firebase** – Conversation memory and cloud storage
* **Apple Speech Framework** – Voice recognition and synthesis
