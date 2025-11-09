"""
Multi-Agent System for LiDAR + Vision Audio Description
Uses Google Gemini API with agent orchestration pattern
"""

import os
import json
import asyncio
import base64
from typing import List, Dict, Any, Optional, Tuple
from dataclasses import dataclass, asdict
from enum import Enum
import numpy as np
from PIL import Image
import io
import google.genai as genai
from datetime import datetime


# ============================================================================
# DATA MODELS
# ============================================================================

class Priority(Enum):
    LOW = 1
    NORMAL = 2
    HIGH = 3
    CRITICAL = 4


@dataclass
class DetectedObject:
    """Represents an object detected in the scene"""
    label: str
    confidence: float
    bbox: Tuple[float, float, float, float]  # x, y, width, height (normalized 0-1)
    distance: Optional[float] = None  # meters
    position_3d: Optional[Tuple[float, float, float]] = None  # x, y, z


@dataclass
class SpatialInfo:
    """Spatial analysis results"""
    nearest_obstacle: Optional[DetectedObject] = None
    path_clear: bool = True
    obstacles_in_path: List[DetectedObject] = None
    average_scene_depth: float = 0.0
    
    def __post_init__(self):
        if self.obstacles_in_path is None:
            self.obstacles_in_path = []


@dataclass
class UserContext:
    """User state and preferences"""
    heading: float = 0.0  # degrees, 0 = north
    speed: float = 0.0  # m/s
    location: Tuple[float, float] = (0.0, 0.0)  # lat, lon
    previous_scene_hash: Optional[str] = None
    detail_level: str = "medium"  # low, medium, high
    preferred_voice: str = "en-US"


@dataclass
class SceneData:
    """Complete scene information"""
    image_base64: str
    depth_map: Optional[np.ndarray] = None
    detected_objects: List[DetectedObject] = None
    timestamp: float = None
    user_context: UserContext = None
    
    def __post_init__(self):
        if self.detected_objects is None:
            self.detected_objects = []
        if self.timestamp is None:
            self.timestamp = datetime.now().timestamp()
        if self.user_context is None:
            self.user_context = UserContext()


@dataclass
class RelevanceScore:
    """Relevance scoring for scene elements"""
    object: DetectedObject
    proximity_score: float  # 0-1
    path_obstruction_score: float  # 0-1
    novelty_score: float  # 0-1
    importance_score: float  # 0-1
    total_score: float = 0.0
    
    def __post_init__(self):
        self.total_score = (
            self.proximity_score * 0.4 +
            self.path_obstruction_score * 0.3 +
            self.novelty_score * 0.2 +
            self.importance_score * 0.1
        )


@dataclass
class AudioDescription:
    """Final audio output"""
    text: str
    priority: Priority
    duration_estimate: float = 0.0
    timestamp: float = None
    
    def __post_init__(self):
        if self.timestamp is None:
            self.timestamp = datetime.now().timestamp()
        # Rough estimate: 150 words per minute
        word_count = len(self.text.split())
        self.duration_estimate = (word_count / 150) * 60


# ============================================================================
# GEMINI API SERVICE
# ============================================================================

class GeminiService:
    """Wrapper for Google Gemini API calls"""
    
    def __init__(self, api_key: str):
        genai.configure(api_key=api_key)
        self.vision_model = genai.GenerativeModel('gemini-1.5-flash')
        self.text_model = genai.GenerativeModel('gemini-1.5-flash')
        
    async def analyze_image(self, image_base64: str, prompt: str) -> str:
        """Analyze image with Gemini Vision"""
        try:
            # Decode base64 to PIL Image
            image_data = base64.b64decode(image_base64)
            image = Image.open(io.BytesIO(image_data))
            
            # Generate content
            response = await asyncio.to_thread(
                self.vision_model.generate_content,
                [prompt, image]
            )
            
            return response.text
        except Exception as e:
            print(f"Vision API error: {e}")
            return f"Error analyzing image: {str(e)}"
    
    async def generate_text(self, prompt: str) -> str:
        """Generate text with Gemini"""
        try:
            response = await asyncio.to_thread(
                self.text_model.generate_content,
                prompt
            )
            return response.text
        except Exception as e:
            print(f"Text generation error: {e}")
            return f"Error generating text: {str(e)}"
    
    async def structured_analysis(self, prompt: str, schema: Dict) -> Dict:
        """Get structured JSON response"""
        try:
            full_prompt = f"{prompt}\n\nRespond ONLY with valid JSON matching this schema: {json.dumps(schema)}"
            response = await self.generate_text(full_prompt)
            
            # Clean response
            cleaned = response.strip()
            if cleaned.startswith("```json"):
                cleaned = cleaned[7:]
            if cleaned.endswith("```"):
                cleaned = cleaned[:-3]
            cleaned = cleaned.strip()
            
            return json.loads(cleaned)
        except json.JSONDecodeError as e:
            print(f"JSON parsing error: {e}")
            return {"error": "Failed to parse response"}
        except Exception as e:
            print(f"Structured analysis error: {e}")
            return {"error": str(e)}


# ============================================================================
# AGENT IMPLEMENTATIONS
# ============================================================================

class VisionAgent:
    """Agent for general scene understanding"""
    
    def __init__(self, gemini_service: GeminiService):
        self.gemini = gemini_service
        self.name = "VisionAgent"
    
    async def analyze(self, scene: SceneData) -> str:
        """Generate general scene description"""
        detail = scene.user_context.detail_level
        
        prompts = {
            "low": "Describe this scene in one brief sentence for navigation assistance.",
            "medium": "Describe this scene concisely for a visually impaired person, focusing on key elements and spatial layout in 2-3 sentences.",
            "high": "Provide a detailed description of this scene for a visually impaired person, including objects, their positions, colors, and any text visible. Be thorough but organized."
        }
        
        prompt = prompts.get(detail, prompts["medium"])
        result = await self.gemini.analyze_image(scene.image_base64, prompt)
        
        print(f"[{self.name}] Generated scene description")
        return result


class ObjectDetectionAgent:
    """Agent for identifying specific objects"""
    
    def __init__(self, gemini_service: GeminiService):
        self.gemini = gemini_service
        self.name = "ObjectDetectionAgent"
    
    async def detect(self, scene: SceneData) -> List[DetectedObject]:
        """Detect and classify objects in scene"""
        
        schema = {
            "objects": [
                {
                    "label": "string",
                    "confidence": "float (0-1)",
                    "position": "string (e.g., 'center', 'left', 'right', 'top', 'bottom')"
                }
            ]
        }
        
        prompt = """Analyze this image and identify all significant objects. 
        For each object, determine:
        - label: what it is
        - confidence: how certain you are (0-1)
        - position: where in the image (left, right, center, top, bottom)
        
        Focus on objects relevant for navigation: furniture, obstacles, doorways, stairs, people, vehicles, etc."""
        
        result = await self.gemini.structured_analysis(prompt, schema)
        
        if "error" in result:
            print(f"[{self.name}] Detection failed: {result['error']}")
            return []
        
        # Convert to DetectedObject list
        objects = []
        for obj in result.get("objects", []):
            # Estimate bbox from position (simplified)
            pos = obj.get("position", "center").lower()
            bbox = self._position_to_bbox(pos)
            
            detected_obj = DetectedObject(
                label=obj.get("label", "unknown"),
                confidence=float(obj.get("confidence", 0.5)),
                bbox=bbox
            )
            objects.append(detected_obj)
        
        print(f"[{self.name}] Detected {len(objects)} objects")
        return objects
    
    def _position_to_bbox(self, position: str) -> Tuple[float, float, float, float]:
        """Convert position string to approximate bbox"""
        # Returns (x, y, width, height) normalized 0-1
        positions = {
            "center": (0.4, 0.4, 0.2, 0.2),
            "left": (0.1, 0.4, 0.2, 0.2),
            "right": (0.7, 0.4, 0.2, 0.2),
            "top": (0.4, 0.1, 0.2, 0.2),
            "bottom": (0.4, 0.7, 0.2, 0.2),
        }
        return positions.get(position, (0.4, 0.4, 0.2, 0.2))


class SpatialAnalysisAgent:
    """Agent for analyzing spatial relationships and depth"""
    
    def __init__(self, gemini_service: GeminiService):
        self.gemini = gemini_service
        self.name = "SpatialAnalysisAgent"
    
    async def analyze(self, scene: SceneData, objects: List[DetectedObject]) -> SpatialInfo:
        """Analyze spatial relationships using depth data"""
        
        # Estimate distances from depth map if available
        if scene.depth_map is not None:
            objects = self._calculate_distances(objects, scene.depth_map)
        else:
            # Use vision model to estimate
            objects = await self._estimate_distances_vision(scene, objects)
        
        # Analyze spatial layout
        spatial_info = self._analyze_spatial_layout(objects, scene.user_context)
        
        print(f"[{self.name}] Analyzed spatial relationships")
        return spatial_info
    
    def _calculate_distances(self, objects: List[DetectedObject], depth_map: np.ndarray) -> List[DetectedObject]:
        """Calculate distances from depth map"""
        for obj in objects:
            # Sample depth at object center
            x, y, w, h = obj.bbox
            center_x = int((x + w/2) * depth_map.shape[1])
            center_y = int((y + h/2) * depth_map.shape[0])
            
            # Clamp to valid range
            center_x = max(0, min(center_x, depth_map.shape[1] - 1))
            center_y = max(0, min(center_y, depth_map.shape[0] - 1))
            
            # Get depth value (assuming depth_map in meters)
            obj.distance = float(depth_map[center_y, center_x])
        
        return objects
    
    async def _estimate_distances_vision(self, scene: SceneData, objects: List[DetectedObject]) -> List[DetectedObject]:
        """Estimate distances using vision model when no depth map"""
        if not objects:
            return objects
        
        object_list = ", ".join([obj.label for obj in objects])
        prompt = f"""Estimate approximate distances in meters to these objects: {object_list}
        
        Respond with JSON:
        {{
            "distances": {{
                "object_label": estimated_meters
            }}
        }}"""
        
        result = await self.gemini.structured_analysis(prompt, {"distances": {}})
        
        distances = result.get("distances", {})
        for obj in objects:
            obj.distance = distances.get(obj.label, 5.0)  # Default 5m
        
        return objects
    
    def _analyze_spatial_layout(self, objects: List[DetectedObject], context: UserContext) -> SpatialInfo:
        """Analyze spatial relationships"""
        
        if not objects:
            return SpatialInfo(path_clear=True)
        
        # Find nearest obstacle
        objects_with_distance = [obj for obj in objects if obj.distance is not None]
        if objects_with_distance:
            nearest = min(objects_with_distance, key=lambda x: x.distance)
        else:
            nearest = None
        
        # Check path obstruction (simplified: center region + close)
        obstacles_in_path = []
        for obj in objects:
            x, y, w, h = obj.bbox
            center_x = x + w/2
            
            # In center third of frame and close
            if 0.33 < center_x < 0.67 and obj.distance and obj.distance < 2.0:
                obstacles_in_path.append(obj)
        
        path_clear = len(obstacles_in_path) == 0
        
        # Calculate average scene depth
        avg_depth = np.mean([obj.distance for obj in objects if obj.distance]) if objects_with_distance else 5.0
        
        return SpatialInfo(
            nearest_obstacle=nearest,
            path_clear=path_clear,
            obstacles_in_path=obstacles_in_path,
            average_scene_depth=float(avg_depth)
        )


class RelevanceRankingAgent:
    """Agent for ranking scene elements by relevance"""
    
    def __init__(self, gemini_service: GeminiService):
        self.gemini = gemini_service
        self.name = "RelevanceRankingAgent"
        self.importance_weights = {
            "person": 1.0,
            "car": 0.9,
            "door": 0.8,
            "stairs": 0.95,
            "chair": 0.5,
            "table": 0.5,
            "sign": 0.85,
            "obstacle": 0.9,
        }
    
    async def rank(self, objects: List[DetectedObject], spatial_info: SpatialInfo, 
                   context: UserContext, scene_description: str) -> List[RelevanceScore]:
        """Rank objects by relevance for audio description"""
        
        scores = []
        for obj in objects:
            score = self._calculate_relevance(obj, spatial_info, context)
            scores.append(score)
        
        # Sort by total score descending
        scores.sort(key=lambda x: x.total_score, reverse=True)
        
        print(f"[{self.name}] Ranked {len(scores)} objects")
        return scores
    
    def _calculate_relevance(self, obj: DetectedObject, spatial_info: SpatialInfo, 
                            context: UserContext) -> RelevanceScore:
        """Calculate relevance score for an object"""
        
        # Proximity score (closer = more relevant)
        if obj.distance is not None:
            proximity = max(0, 1 - (obj.distance / 10.0))  # 10m max range
        else:
            proximity = 0.5
        
        # Path obstruction (in path = more relevant)
        in_path = obj in spatial_info.obstacles_in_path
        path_score = 1.0 if in_path else 0.3
        
        # Novelty (simplified: always 0.5 for now, would need history)
        novelty = 0.5
        
        # Importance based on object type
        importance = 0.5
        for key, weight in self.importance_weights.items():
            if key.lower() in obj.label.lower():
                importance = weight
                break
        
        return RelevanceScore(
            object=obj,
            proximity_score=proximity,
            path_obstruction_score=path_score,
            novelty_score=novelty,
            importance_score=importance
        )


class NarrationComposerAgent:
    """Agent for composing natural audio narration"""
    
    def __init__(self, gemini_service: GeminiService):
        self.gemini = gemini_service
        self.name = "NarrationComposerAgent"
    
    async def compose(self, scene_description: str, ranked_objects: List[RelevanceScore],
                     spatial_info: SpatialInfo, context: UserContext) -> str:
        """Compose natural narration from analyzed data"""
        
        # Prepare ranked elements description
        top_objects = ranked_objects[:5]  # Top 5 most relevant
        elements_text = []
        
        for score in top_objects:
            obj = score.object
            dist_text = f"{obj.distance:.1f} meters" if obj.distance else "nearby"
            elements_text.append(f"- {obj.label} at {dist_text} (relevance: {score.total_score:.2f})")
        
        elements_summary = "\n".join(elements_text)
        
        # Determine urgency
        has_obstacles = not spatial_info.path_clear
        urgency = "URGENT: " if has_obstacles else ""
        
        detail_instructions = {
            "low": "one brief sentence",
            "medium": "2-3 clear sentences",
            "high": "a detailed but organized description"
        }
        detail = detail_instructions.get(context.detail_level, "2-3 clear sentences")
        
        prompt = f"""{urgency}Create a natural audio description for a visually impaired person navigating this environment.

Scene Overview:
{scene_description}

Most Relevant Elements (prioritize these):
{elements_summary}

Path Status: {"BLOCKED - obstacles ahead" if has_obstacles else "Clear"}
Nearest Obstacle: {spatial_info.nearest_obstacle.label if spatial_info.nearest_obstacle else "None"}

Instructions:
- Use {detail}
- Prioritize obstacles and navigation hazards
- Use natural, conversational language
- Include distances when important
- Be concise but informative
- Start with most critical information

Generate the audio description:"""
        
        narration = await self.gemini.generate_text(prompt)
        
        print(f"[{self.name}] Composed narration")
        return narration.strip()


# ============================================================================
# AGENT ORCHESTRATOR
# ============================================================================

class AgentOrchestrator:
    """Orchestrates all agents to process scene data"""
    
    def __init__(self, api_key: str):
        self.gemini = GeminiService(api_key)
        
        # Initialize agents
        self.vision_agent = VisionAgent(self.gemini)
        self.object_agent = ObjectDetectionAgent(self.gemini)
        self.spatial_agent = SpatialAnalysisAgent(self.gemini)
        self.relevance_agent = RelevanceRankingAgent(self.gemini)
        self.narration_agent = NarrationComposerAgent(self.gemini)
        
        print("AgentOrchestrator initialized with all agents")
    
    async def process_scene(self, scene: SceneData) -> AudioDescription:
        """Main orchestration flow"""
        print(f"\n{'='*60}")
        print(f"Processing scene at {datetime.fromtimestamp(scene.timestamp)}")
        print(f"{'='*60}\n")
        
        try:
            # Stage 1: Parallel vision analysis and object detection
            print("Stage 1: Vision Analysis & Object Detection (parallel)")
            vision_task = self.vision_agent.analyze(scene)
            objects_task = self.object_agent.detect(scene)
            
            scene_description, detected_objects = await asyncio.gather(
                vision_task, objects_task
            )
            
            # Update scene with detected objects
            scene.detected_objects = detected_objects
            
            # Stage 2: Spatial analysis
            print("\nStage 2: Spatial Analysis")
            spatial_info = await self.spatial_agent.analyze(scene, detected_objects)
            
            # Stage 3: Relevance ranking
            print("\nStage 3: Relevance Ranking")
            ranked_objects = await self.relevance_agent.rank(
                detected_objects, spatial_info, scene.user_context, scene_description
            )
            
            # Stage 4: Narration composition
            print("\nStage 4: Narration Composition")
            narration = await self.narration_agent.compose(
                scene_description, ranked_objects, spatial_info, scene.user_context
            )
            
            # Determine priority
            priority = self._determine_priority(spatial_info, ranked_objects)
            
            # Create audio description
            audio_desc = AudioDescription(
                text=narration,
                priority=priority
            )
            
            print(f"\n{'='*60}")
            print(f"Processing complete: {len(narration)} characters")
            print(f"Priority: {priority.name}")
            print(f"{'='*60}\n")
            
            return audio_desc
            
        except Exception as e:
            print(f"\nERROR in orchestration: {e}")
            return AudioDescription(
                text=f"Navigation assistance temporarily unavailable: {str(e)}",
                priority=Priority.LOW
            )
    
    def _determine_priority(self, spatial_info: SpatialInfo, 
                          ranked_objects: List[RelevanceScore]) -> Priority:
        """Determine urgency level"""
        
        # Critical: obstacles very close
        if spatial_info.nearest_obstacle and spatial_info.nearest_obstacle.distance:
            if spatial_info.nearest_obstacle.distance < 1.0:
                return Priority.CRITICAL
        
        # High: path blocked
        if not spatial_info.path_clear:
            return Priority.HIGH
        
        # High: high-relevance objects detected
        if ranked_objects and ranked_objects[0].total_score > 0.8:
            return Priority.HIGH
        
        return Priority.NORMAL


# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

def image_to_base64(image_path: str) -> str:
    """Convert image file to base64 string"""
    with open(image_path, "rb") as f:
        return base64.b64encode(f.read()).decode('utf-8')


def create_mock_depth_map(width: int = 640, height: int = 480) -> np.ndarray:
    """Create a mock depth map for testing"""
    # Simulate depth with gradient (closer at bottom, farther at top)
    depth = np.linspace(10, 2, height).reshape(-1, 1)
    depth = np.tile(depth, (1, width))
    # Add some noise
    depth += np.random.normal(0, 0.5, (height, width))
    return np.clip(depth, 0.5, 15.0)


# ============================================================================
# EXAMPLE USAGE
# ============================================================================

async def main():
    """Example usage of the multi-agent system"""
    
    # Initialize
    API_KEY = os.getenv("GOOGLE_API_KEY", "your-api-key-here")
    
    if API_KEY == "your-api-key-here":
        print("ERROR: Set GOOGLE_API_KEY environment variable")
        print("export GOOGLE_API_KEY='your-actual-api-key'")
        return
    
    orchestrator = AgentOrchestrator(API_KEY)
    
    # Example 1: Process image file
    print("\n" + "="*60)
    print("EXAMPLE 1: Processing image file")
    print("="*60)
    
    # You would provide your own image here
    # For demo purposes, create a simple test image
    test_image = Image.new('RGB', (640, 480), color='lightblue')
    buffer = io.BytesIO()
    test_image.save(buffer, format='PNG')
    image_base64 = base64.b64encode(buffer.getvalue()).decode('utf-8')
    
    # Create scene data
    scene = SceneData(
        image_base64=image_base64,
        depth_map=create_mock_depth_map(),
        user_context=UserContext(
            heading=90.0,
            speed=1.2,
            detail_level="medium"
        )
    )
    
    # Process scene
    audio_description = await orchestrator.process_scene(scene)
    
    # Display results
    print("\n" + "="*60)
    print("FINAL AUDIO DESCRIPTION")
    print("="*60)
    print(f"Priority: {audio_description.priority.name}")
    print(f"Duration: {audio_description.duration_estimate:.1f} seconds")
    print(f"\nText:\n{audio_description.text}")
    print("="*60)
    
    # Example 2: Batch processing
    print("\n" + "="*60)
    print("EXAMPLE 2: Batch processing multiple scenes")
    print("="*60)
    
    scenes = []
    for i in range(3):
        test_img = Image.new('RGB', (640, 480), 
                            color=['lightblue', 'lightgreen', 'lightyellow'][i])
        buf = io.BytesIO()
        test_img.save(buf, format='PNG')
        img_b64 = base64.b64encode(buf.getvalue()).decode('utf-8')
        
        scenes.append(SceneData(
            image_base64=img_b64,
            depth_map=create_mock_depth_map(),
            user_context=UserContext(detail_level="low")
        ))
    
    # Process in parallel
    results = await asyncio.gather(*[
        orchestrator.process_scene(scene) for scene in scenes
    ])
    
    for i, result in enumerate(results):
        print(f"\nScene {i+1}: {result.text[:100]}...")


if __name__ == "__main__":
    print("Multi-Agent LiDAR Vision System")
    print("=" * 60)
    asyncio.run(main())