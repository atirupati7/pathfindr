# PathFindr

PathFindr is an iOS app that helps visually impaired users navigate their surroundings using ARKit, LiDAR depth sensing, and AI-powered visual descriptions. The app provides real-time audio guidance, object detection, and conversational AI assistance through voice commands.

## Features

### Core Navigation
- **AR-Based Navigation**: Uses ARKit and LiDAR to detect obstacles and guide users
- **Real-Time Depth Sensing**: Calculates distances to objects using LiDAR data
- **Spatial Audio Guidance**: Provides directional audio cues for navigation
- **Obstacle Detection**: Identifies and warns about objects in the user's path

### AI-Powered Assistance
- **Gemini AI Integration**: Uses Google's Gemini 2.0 Flash model for visual understanding
- **Streaming Descriptions**: Continuously describes the environment when guidance is active
- **Voice Prompts**: Ask questions about your surroundings using voice commands
- **Conversation Memory**: Remembers previous interactions using Firebase
- **Image History**: Stores last 5 images from conversations for contextual follow-up questions
- **OCR Support**: Reads text from signs, menus, and crosswalk signals

### Voice Interaction
- **Hold-to-Speak Button**: Press and hold the on-screen button to ask questions
- **Speech Recognition**: Transcribes voice input using Apple's Speech framework
- **Text-to-Speech**: Speaks AI responses and navigation guidance
- **Smart Interruption**: Automatically stops streaming descriptions when recording

### User Experience
- **Full-Screen Camera Preview**: Live video feed of the camera view
- **Movement Detection**: Only announces objects when the user is moving
- **Distance Announcements**: Includes distance measurements with object descriptions
- **Visual Feedback**: Shows recording status and transcriptions

## Requirements

- iOS 18.6 or later
- iPhone with LiDAR sensor (iPhone 12 Pro or later)
- Google Gemini API key
- Firebase project (for conversation history)
- Xcode 15.0 or later

## Setup

### 1. Clone the Repository

```bash
git clone https://github.com/atirupati7/pathfindr.git
cd pathfindr
```

### 2. Install Dependencies

The project uses Swift Package Manager for Firebase dependencies:

1. Open `PathFindr.xcodeproj` in Xcode
2. Go to **File** > **Add Package Dependencies**
3. Add: `https://github.com/firebase/firebase-ios-sdk`
4. Select **FirebaseCore** and **FirebaseFirestore**
5. Click **Add Package**

### 3. Configure API Keys

1. Copy `PathFindr/System/APIKeys.example.swift` to `PathFindr/System/APIKeys.swift`
2. Add your Gemini API key:
   ```swift
   static let geminiAPIKey = "YOUR_GEMINI_API_KEY_HERE"
   ```
3. Get your Gemini API key from [Google AI Studio](https://makersuite.google.com/app/apikey)

### 4. Configure Firebase

1. Create a Firebase project at [Firebase Console](https://console.firebase.google.com/)
2. Add an iOS app with bundle identifier: `com.atirupati07.pathfindr`
3. Download `GoogleService-Info.plist` from Firebase Console
4. Copy `PathFindr/GoogleService-Info.example.plist` to `PathFindr/GoogleService-Info.plist` and fill in your Firebase credentials
5. Enable Firestore Database in Firebase Console
5. Set up Firestore security rules (test mode for development):
   ```
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

1. Open the project in Xcode
2. Select your development team in the project settings
3. Connect your iPhone (with LiDAR) via USB
4. Build and run (Cmd+R)

## Usage

### Starting Navigation

1. Launch the app
2. Grant camera, microphone, and motion permissions
3. Tap **"Start Guidance"** to begin navigation
4. The app will start describing your surroundings

### Asking Questions

1. Press and hold the **blue microphone button** on the screen
2. Speak your question (e.g., "What is this?", "What color was the MacBook?")
3. Release the button when finished
4. The app will process your question and speak the answer

### Features in Action

- **Streaming Mode**: When guidance is active, the app continuously describes objects and distances
- **Prompt Mode**: When you ask a question, streaming stops and the app focuses on answering
- **Memory**: The app remembers previous conversations, so you can ask follow-up questions
- **Image Context**: The app uses the last 5 images from your conversation history for context

## Architecture

### Key Components

- **Navigator**: Main coordinator that manages AR, speech, and AI interactions
- **ARDepthSession**: Handles ARKit session and depth data processing
- **GeminiClient**: Communicates with Google Gemini API for visual understanding
- **FirebaseConversationService**: Manages conversation history storage and retrieval
- **SpeechTranscriber**: Handles voice input transcription
- **SpeechGuide**: Handles text-to-speech output
- **MotionHeading**: Tracks device orientation and user movement

### Data Flow

1. **AR Frames**: ARKit provides camera frames and depth data
2. **Streaming Descriptions**: Gemini analyzes frames and provides object descriptions
3. **Voice Input**: User presses hold button → speech is transcribed → sent to Gemini
4. **Conversation History**: Previous exchanges (with images) are retrieved from Firebase
5. **AI Response**: Gemini responds with context from history → text-to-speech output
6. **Storage**: New exchanges are saved to Firebase with images

## Project Structure

```
PathFindr/
├── App/
│   └── MainApp.swift              # App entry point with Firebase initialization
├── AI/
│   └── GeminiClient.swift         # Gemini API integration
├── AR/
│   └── ARDepthSession.swift       # ARKit session management
├── Coordinator/
│   └── Navigator.swift            # Main navigation coordinator
├── Guidance/
│   ├── SpeechGuide.swift          # Text-to-speech
│   ├── SpatialBeacon.swift        # Spatial audio guidance
│   └── Haptics.swift              # Haptic feedback
├── Mapping/
│   ├── FloorEstimator.swift       # Floor detection
│   └── OccupancyGrid.swift        # Obstacle mapping
├── Perception/
│   ├── ObjectDetector.swift       # Object detection
│   └── DepthFusion.swift          # Depth data processing
├── Planning/
│   ├── AStar.swift                # Pathfinding algorithm
│   └── CommandSynthesizer.swift   # Navigation commands
├── System/
│   ├── APIKeys.swift              # API keys configuration
│   ├── FirebaseConversationService.swift  # Conversation history
│   ├── MotionHeading.swift        # Motion tracking
│   └── SpeechTranscriber.swift    # Voice input
├── ContentView.swift              # Main UI with hold-to-speak button
├── Info.plist                     # App configuration
├── GoogleService-Info.plist       # Firebase configuration (not in repo)
└── GoogleService-Info.example.plist  # Firebase configuration template
```

## Configuration

### API Keys

Create `PathFindr/System/APIKeys.swift`:
```swift
struct APIKeys {
    static let geminiAPIKey = "YOUR_GEMINI_API_KEY_HERE"
    static let firebaseAPIKey = "YOUR_FIREBASE_API_KEY"
    static let firebaseAppID = "YOUR_FIREBASE_APP_ID"
    static let firebaseProjectID = "YOUR_FIREBASE_PROJECT_ID"
    static let firebaseMessagingSenderID = "YOUR_FIREBASE_SENDER_ID"
}
```

### Firebase Setup

1. Initialize Firebase in `MainApp.swift` (already done)
2. Enable Firestore in Firebase Console
3. Configure security rules for your use case
4. The app uses `default_user` as the user ID (can be customized for multi-user support)

## Troubleshooting

### App Icon Not Showing
- Delete the app from your device
- Clean build folder in Xcode (Cmd+Shift+K)
- Rebuild and reinstall

### Firebase Not Working
- Verify `GoogleService-Info.plist` is in the project and added to target
- Check that Firestore is enabled in Firebase Console
- Verify security rules allow read/write operations
- Check Xcode console for Firebase errors

### Voice Input Not Working
- Grant microphone and speech recognition permissions
- Check that the hold button is responding (should turn red when pressed)
- Verify audio session permissions in Settings

### Low Volume
- Check device volume settings
- The app uses maximum volume setting (1.0)
- Audio session is configured for playback mode

### Memory Not Working
- Verify Firebase is properly configured
- Check that images are being saved to Firestore
- Look for Firebase errors in the console
- Ensure Firestore security rules allow write operations

## Development

### Building for Device

1. Connect iPhone with LiDAR via USB
2. Select your development team in Xcode
3. Select your device as the build target
4. Build and run (Cmd+R)

### Testing

- Test on a physical device with LiDAR (simulator doesn't support ARKit/LiDAR)
- Grant all required permissions
- Test voice input in a quiet environment
- Verify Firebase connection and data storage

## License

This project is part of a hackathon submission.

## Acknowledgments

- Google Gemini API for visual understanding
- Firebase for conversation history storage
- Apple ARKit for spatial awareness
- Apple Speech Framework for voice recognition
