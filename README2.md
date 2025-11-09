# PathFindr - Technical Summary

## Overview

PathFindr is an iOS application that helps visually impaired users navigate their surroundings using ARKit, LiDAR depth sensing, and AI-powered visual descriptions. The app provides real-time audio guidance, object detection, and conversational AI assistance through voice commands.

## Architecture

### System Components

**iOS Frontend (Primary):**
- Real-time AR/LiDAR processing using ARKit
- Direct integration with Google Gemini API for visual understanding
- Voice input/output using Apple Speech Framework
- Firebase Firestore for conversation history storage
- Local pathfinding and obstacle detection

**Python Backend (Optional):**
- Flask REST API for advanced multi-agent AI processing
- Multi-agent system for hazard detection, semantic understanding, and scene analysis
- Can be used for more complex scene analysis scenarios

## Frontend-Backend Interaction

### Current Implementation

The iOS app primarily uses **direct Gemini API integration** for most features:

1. **Streaming Descriptions**: iOS app sends camera frames directly to Gemini API every 5 seconds
2. **Voice Prompts**: User questions are sent directly to Gemini API with conversation history
3. **Conversation Memory**: Stored in Firebase Firestore, retrieved by iOS app before sending to Gemini

### Backend Integration (Optional)

The Python backend (`adk_backend`) provides an alternative processing pipeline:

**API Endpoint**: `POST /api/v1/pathfinder`

**Request Format:**
```json
{
  "objects": [
    {"label": "person", "distance_m": 1.2, "direction_deg": -10},
    {"label": "chair", "distance_m": 0.6, "direction_deg": 20}
  ],
  "free_space": {"center_m": 0.8, "left_m": 1.5, "right_m": 2.0}
}
```

**Response:**
```json
{
  "message": "AI-generated navigation guidance",
  "request_id": "uuid"
}
```

**Backend Processing Flow:**
1. Receives scene data (objects, distances, free space) from iOS app
2. Coordinates multiple AI agents:
   - **HazardDetector**: Identifies immediate hazards
   - **SemanticAgent**: Generates environment descriptions
   - **ImageSceneAgent**: Analyzes camera images (if provided)
3. Uses **AdaptivePromptAgent** to orchestrate agents based on user prompt
4. Returns prioritized, concise navigation guidance

**Integration Options:**
- **Option A (Current)**: iOS app uses Gemini API directly (simpler, lower latency)
- **Option B (Advanced)**: iOS app sends scene data to backend Flask API for multi-agent processing (more complex analysis, higher latency)

### Data Flow

```
iOS App → ARKit/LiDAR → Scene Data
    ↓
[Direct Path]                    [Backend Path]
    ↓                                    ↓
Gemini API                      Flask API → Multi-Agent System → Gemini API
    ↓                                    ↓
Response                          Response
    ↓                                    ↓
Text-to-Speech                    Text-to-Speech
```

## Key Features

### Core Navigation
- **AR-Based Navigation**: ARKit and LiDAR for obstacle detection
- **Real-Time Depth Sensing**: Calculates distances using LiDAR data
- **Spatial Audio Guidance**: 3D audio beacons for directional cues
- **Haptic Feedback**: Proximity pulses and danger alerts
- **Pathfinding**: A* algorithm for route planning

### AI-Powered Assistance
- **Gemini AI Integration**: Google Gemini 2.0 Flash for visual understanding
- **Streaming Descriptions**: Continuous environment descriptions (5-second intervals)
- **Voice Prompts**: Ask questions about surroundings
- **Conversation Memory**: Remembers previous interactions (last 5 exchanges with images)
- **OCR Support**: Reads text from signs, menus, crosswalk signals

### Voice Interaction
- **Hold-to-Speak Button**: On-screen button for voice input
- **Speech Recognition**: Apple Speech Framework
- **Text-to-Speech**: AVSpeechSynthesizer with maximum volume
- **Smart Interruption**: Automatically pauses streaming when recording

### User Experience
- **Full-Screen Camera Preview**: Live AR camera feed
- **Movement Detection**: Only announces objects when user is moving
- **Distance Announcements**: Includes distance measurements with descriptions
- **Visual Feedback**: Recording status and transcriptions

## Project Structure

### iOS Application
```
PathFindr/
├── App/                    # App entry point
├── AI/                     # Gemini API integration
├── AR/                     # ARKit session management
├── Coordinator/            # Main navigation coordinator
├── Guidance/               # Speech, spatial audio, haptics
├── Mapping/                # Occupancy grid, floor detection
├── Perception/             # Object detection, depth processing
├── Planning/               # A* pathfinding, command synthesis
└── System/                 # API keys, Firebase, motion tracking
```

### Backend Service
```
adk_backend/
├── src/
│   ├── app.py              # Flask application
│   ├── gemini_api.py       # Gemini API wrapper
│   ├── hazard_agent.py     # Hazard detection
│   ├── semantic_agent.py   # Scene understanding
│   ├── image_agent.py      # Image analysis
│   └── prompt_agent.py     # Adaptive agent coordination
```

## Technology Stack

### iOS Frontend
- **Swift/SwiftUI**: UI framework
- **ARKit**: AR and LiDAR processing
- **AVFoundation**: Speech recognition, text-to-speech, spatial audio
- **CoreMotion**: Device orientation and movement detection
- **Vision Framework**: Object detection
- **Firebase SDK**: Firestore for conversation history
- **Google Gemini API**: Visual understanding and NLP

### Backend
- **Python 3.8+**: Programming language
- **Flask**: REST API framework
- **Google Gemini API**: AI processing
- **AsyncIO**: Concurrent agent execution

### Infrastructure
- **Firebase Firestore**: Conversation history and image storage
- **Google Gemini API**: Vision and language models

## Setup

### iOS Application

1. **Install Dependencies:**
   - Open `PathFindr.xcodeproj` in Xcode
   - Add Firebase SDK: `https://github.com/firebase/firebase-ios-sdk`
   - Select `FirebaseCore` and `FirebaseFirestore`

2. **Configure API Keys:**
   - Copy `PathFindr/System/APIKeys.example.swift` to `PathFindr/System/APIKeys.swift`
   - Add your Gemini API key

3. **Configure Firebase:**
   - Copy `PathFindr/GoogleService-Info.example.plist` to `PathFindr/GoogleService-Info.plist`
   - Fill in Firebase credentials from Firebase Console
   - Enable Firestore Database

4. **Build and Run:**
   - Connect iPhone with LiDAR via USB
   - Build and run in Xcode

### Backend Service (Optional)

1. **Install Dependencies:**
   ```bash
   cd adk_backend
   pip install flask google-generativeai werkzeug
   ```

2. **Configure Environment:**
   ```bash
   export GOOGLE_API_KEY="your_gemini_api_key"
   ```

3. **Run Server:**
   ```bash
   python src/app.py
   # Server runs on http://0.0.0.0:5000
   ```

## Usage

### Starting Navigation
1. Launch the app
2. Grant camera, microphone, and motion permissions
3. Tap "Start Guidance" to begin navigation
4. App starts describing surroundings with distances

### Asking Questions
1. Press and hold the blue microphone button
2. Speak your question (e.g., "What is this?", "What color was the MacBook?")
3. Release the button when finished
4. App processes question and speaks the answer

### Features in Action
- **Streaming Mode**: Continuously describes objects and distances when guidance is active
- **Prompt Mode**: Stops streaming and focuses on answering user questions
- **Memory**: Remembers previous conversations for follow-up questions
- **Image Context**: Uses last 5 images from conversation history for context

## Data Storage

### Firebase Firestore Structure
```
conversations/
  {userId}/
    exchanges/
      {exchangeId}/
        userPrompt: string
        assistantResponse: string
        imageData: string (base64 encoded JPEG)
        timestamp: timestamp
```

### Conversation Memory
- Stores last 5 exchanges with images
- Images encoded as Base64 strings
- Retrieved before each prompted query
- Used to provide context for follow-up questions

## API Integration

### Gemini API
- **Model**: `gemini-2.0-flash`
- **Streaming**: 5-second intervals, compressed JPEG images
- **Prompted**: Includes conversation history and previous images
- **Response**: Text descriptions suitable for text-to-speech

### Backend API (Optional)
- **Endpoint**: `POST /api/v1/pathfinder`
- **Input**: Scene data (objects, distances, free space) + optional image
- **Processing**: Multi-agent AI system
- **Output**: Prioritized navigation guidance

## Key Algorithms

### Pathfinding
- **A* Algorithm**: Grid-based pathfinding with 8-directional movement
- **Occupancy Grid**: 4m × 6m grid with 0.1m resolution
- **Command Synthesis**: Converts path to turn degrees and forward distance

### Depth Processing
- **Depth Integration**: Converts LiDAR depth maps to 2D occupancy grid
- **Floor Estimation**: Estimates floor height from depth data
- **Object Detection**: Vision Framework for rectangle detection

### Movement Detection
- **Acceleration Analysis**: Tracks user acceleration magnitude
- **Sample Window**: 20 samples, 0.1 m/s² threshold
- **Smart Announcements**: Only announces objects when user is moving

## Performance Considerations

- **AR Frame Processing**: Throttled to 20 FPS
- **Gemini API Calls**: 5-second interval for streaming
- **Image Compression**: 0.6-0.7 quality for faster upload
- **Depth Integration**: 2×2 pixel stride for performance
- **Grid Resolution**: 0.1m balance between accuracy and performance

## Security

- **API Keys**: Stored in gitignored files
- **Firebase Rules**: Configure Firestore security rules
- **User Data**: Images stored as Base64 in Firestore
- **Network**: HTTPS for all API calls
- **Permissions**: Request camera, microphone, speech recognition permissions

## Future Enhancements

- Multi-user support with authentication
- Offline mode with local AI models
- Destination-based navigation
- Integration with other assistive technologies
- Advanced analytics and machine learning

## License

This project is part of a hackathon submission.

## Acknowledgments

- Google Gemini API for visual understanding
- Firebase for conversation history storage
- Apple ARKit for spatial awareness
- Apple Speech Framework for voice recognition

