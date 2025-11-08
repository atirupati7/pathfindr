# PathFindr

Assistive AR navigation for blind/visually impaired users. Offline, on-device.

## Features
- LiDAR / ARKit depth integration to 2D occupancy grid
- Object detection via Vision
- Path planning (A*) and micro command synthesis
- Speech guidance + spatial audio beacon + haptics
- Safety stop for near obstacles

## Running
Open in Xcode (iOS 16+ device required for best performance). Provide Info.plist keys:
```
NSCameraUsageDescription
NSMotionUsageDescription
```
Enable Background Audio mode.

## Tests
Xcode test target includes AStar, DepthFusion, CommandSynthesizer tests.

## Next Steps
- Floor plane using ARMesh anchors & classification
- Drop-off detection
- Narrow passage state refinement
- Energy optimizations
