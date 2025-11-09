import os
import asyncio
import json
from dataclasses import dataclass
from typing import List, Dict, Any
from datetime import datetime
import google.generativeai as genai
from vertexai.preview.vision_models import Image
from vertexai.preview import generative_models as gemini
from typing import Optional
from PIL import Image as PILImage


# ============================================================================
# LIGHTWEIGHT GEMINI SERVICE
# ============================================================================

class LightweightGeminiService:
    """Minimal Gemini API wrapper with usage tracking"""
    
    def __init__(self, api_key: str):
        genai.configure(api_key=api_key)
        self.model_name = 'gemini-2.0-flash-lite'  # Using flash for lower cost
        self.model = genai.GenerativeModel(self.model_name)
    
    async def generate(self, prompt: str, agent_name: str) -> str:
        """Generate text and track usage"""
        try:
            response = await asyncio.to_thread(
                self.model.generate_content,
                prompt
            )
            
            # Estimate token counts (rough approximation)
            # prompt_tokens = len(prompt.split()) * 1.3  # ~1.3 tokens per word
            # response_tokens = len(response.text.split()) * 1.3
            
            # self.tracker.log_call(
            #     agent_name=agent_name,
            #     model=self.model_name,
            #     prompt_tokens=int(prompt_tokens),
            #     response_tokens=int(response_tokens)
            # )
            
            return response.text
            
        except Exception as e:
            print(f"❌ API Error in {agent_name}: {e}")
            return f"Error: {str(e)}"


# ============================================================================
# SIMPLE AGENTS
# ============================================================================


import asyncio
from vertexai.preview.vision_models import Image

class ImageSceneAgent:
    """
    Uses Gemini 2.0 Flash Lite (via LightweightGeminiService) for visual scene understanding.
    Works with local image files (converted to PIL format).
    """

    def __init__(self, gemini: LightweightGeminiService):
        self.gemini = gemini
        self.name = "ImageSceneAgent"

    async def describe(self, image_path: str, context: str = "") -> str:
        """
        Analyze an image with optional contextual text (e.g., LiDAR or sensor data).
        Returns a concise scene description suitable for narration or hazard awareness.
        """
        print(f"📷 {self.name}: analyzing {image_path}")

        try:
            # ✅ Convert to PIL.Image.Image
            image_obj = PILImage.open(image_path)

            prompt = (
                "You are an AI vision assistant for visually impaired users. "
                "Describe this image in 3-4 sentences, focusing on spatial layout, "
                "colors, and the general vibe. "
                "If possible, describe relative positions (e.g., 'person on the left', "
                "'door ahead')."
            )

            if context:
                prompt += f"\n\nAdditional sensor context:\n{context}"

            # Run generation (async-safe)
            response = await asyncio.to_thread(
                self.gemini.model.generate_content,
                [prompt, image_obj]
            )

            print(f"✓ {self.name} completed")
            return response.text

        except Exception as e:
            print(f"❌ {self.name} error: {e}")
            return f"Error: {str(e)}"


class HazardDetector:
    def __init__(self, gemini):
        self.gemini = gemini
        self.name = "HazardDetector"

    async def detect(self, scene_data: Dict[str, Any]) -> str:
        """Detect immediate hazards using distance + direction info."""
        prompt = (
            "You are a hazard detection module for a blind-assistance system. "
            "Given the detected objects with distances and directions, identify the top 2-3 most immediate hazards. "
            "Respond concisely in plain English suitable for audio narration.\n\n"
            f"Scene data:\n{scene_data}"
        )
        result = await self.gemini.generate(prompt, self.name)
        print(f"✓ {self.name} completed")
        return result


class SemanticAgent:
    def __init__(self, gemini):
        self.gemini = gemini
        self.name = "SemanticAgent"

    async def describe(self, scene_data: Dict[str, Any]) -> str:
        """Generate a natural description of the environment."""
        prompt = (
            "You are a scene interpretation agent. "
            "Given a list of detected objects and spatial layout, describe the environment in a natural and helpful way. "
            "Focus on overall context (room type, relative layout, notable objects) rather than small details.\n\n"
            f"Scene data:\n{scene_data}"
        )
        result = await self.gemini.generate(prompt, self.name)
        print(f"✓ {self.name} completed")
        return result


class PrioritizationAgent:
    def __init__(self, gemini):
        self.gemini = gemini
        self.name = "PrioritizationAgent"

    async def prioritize(self, hazard_text: str, semantic_text: str, image_text: str) -> str:
        """Order information for narration by urgency and relevance."""
        prompt = (
            "You are a prioritization system deciding how to order narration for a blind-assistance AI. "
            "Given a hazard report and a scene description, output a single combined narration. "
            "List the most urgent warnings first, followed by semantic context. "
            "Keep it concise, intuitive, and easy to speak.\n\n"
            f"Hazard report:\n{hazard_text}\n\n"
            f"Scene description:\n{semantic_text}\n\n"
            f"Image description:\n{image_text}"
        )
        result = await self.gemini.generate(prompt, self.name)
        print(f"✓ {self.name} completed")
        return result


# class AnalyzerAgent:
#     """Analyzes input and extracts key information"""
    
#     def __init__(self, gemini: LightweightGeminiService):
#         self.gemini = gemini
#         self.name = "AnalyzerAgent"
    
#     async def analyze(self, text: str) -> str:
#         """Analyze text input"""
#         prompt = f"Analyze this text in 2-3 sentences: {text}"
#         result = await self.gemini.generate(prompt, self.name)
#         print(f"✓ {self.name} completed")
#         return result


# class SummarizerAgent:
#     """Summarizes information concisely"""
    
#     def __init__(self, gemini: LightweightGeminiService):
#         self.gemini = gemini
#         self.name = "SummarizerAgent"
    
#     async def summarize(self, text: str) -> str:
#         """Create brief summary"""
#         prompt = f"Summarize in one sentence: {text}"
#         result = await self.gemini.generate(prompt, self.name)
#         print(f"✓ {self.name} completed")
#         return result


# class SynthesizerAgent:
#     """Synthesizes multiple inputs into final output"""
    
#     def __init__(self, gemini: LightweightGeminiService):
#         self.gemini = gemini
#         self.name = "SynthesizerAgent"
    
#     async def synthesize(self, analysis: str, summary: str) -> str:
#         """Combine analysis and summary"""
#         prompt = f"Combine these insights into one coherent response:\nAnalysis: {analysis}\nSummary: {summary}"
#         result = await self.gemini.generate(prompt, self.name)
#         print(f"✓ {self.name} completed")
#         return result


class CentralCoordinator:
    def __init__(self, gemini):
        self.hazard_agent = HazardDetector(gemini)
        self.semantic_agent = SemanticAgent(gemini)
        self.image_agent = ImageSceneAgent(gemini)
        self.prioritization_agent = PrioritizationAgent(gemini)
        # self.narrator_agent = NarratorAgent(gemini)

    async def process_scene(self, scene_data):
        """Run all agents in sequence."""
        # Run hazard and semantic in parallel
        hazard_task = asyncio.create_task(self.hazard_agent.detect(scene_data))
        semantic_task = asyncio.create_task(self.semantic_agent.describe(scene_data))
        image_task = asyncio.create_task(self.image_agent.describe('files/IMG_9866.png'))

        hazard_text, semantic_text, image_text = await asyncio.gather(hazard_task, semantic_task, image_task)

        prioritized = await self.prioritization_agent.prioritize(hazard_text, semantic_text, image_text)
        # narrated = await self.narrator_agent.narrate(prioritized)

        return {
            "hazards": hazard_text,
            "scene": semantic_text,
            "final_output": prioritized
        }


# ============================================================================
# LIGHTWEIGHT ORCHESTRATOR
# ============================================================================

# class SimpleOrchestrator:
#     """Coordinates agents with minimal overhead"""
    
#     def __init__(self, api_key: str):
#         self.gemini = LightweightGeminiService(api_key)
#         self.analyzer = AnalyzerAgent(self.gemini)
#         self.summarizer = SummarizerAgent(self.gemini)
#         self.synthesizer = SynthesizerAgent(self.gemini)
    
#     async def process(self, input_text: str) -> str:
#         """Process input through agent pipeline"""
#         print("\n🚀 Starting multi-agent pipeline...")
#         print("-" * 60)
        
#         # Stage 1: Parallel analysis and summarization
#         print("Stage 1: Running Analyzer and Summarizer (parallel)...")
#         analysis, summary = await asyncio.gather(
#             self.analyzer.analyze(input_text),
#             self.summarizer.summarize(input_text)
#         )
        
#         # Stage 2: Synthesize results
#         print("Stage 2: Running Synthesizer...")
#         final_result = await self.synthesizer.synthesize(analysis, summary)
        
#         print("-" * 60)
#         print("✅ Pipeline complete\n")
        
#         return final_result


async def main():
    # Initialize Gemini wrapper
    api_key = os.getenv("GOOGLE_API_KEY")
    gemini = LightweightGeminiService(api_key=api_key)
    coordinator = CentralCoordinator(gemini)

    # Example input (from iPhone frontend)
    scene_data = {
        "objects": [
            {"label": "person", "distance_m": 1.2, "direction_deg": -10},
            {"label": "chair", "distance_m": 0.6, "direction_deg": 20},
            {"label": "wall", "distance_m": 1.5, "direction_deg": 0}
        ],
        "free_space": {"center_m": 0.8, "left_m": 1.5, "right_m": 2.0}
    }

    output = await coordinator.process_scene(scene_data)
    print("\n🗣 Final Narration:\n", output["final_output"])


# async def main():

#     input_text = "Artificial intelligence is transforming healthcare through machine learning models that can analyze medical images, predict patient outcomes, and assist in diagnosis."

#     api_key = os.getenv("GOOGLE_API_KEY")
#     orchestrator = SimpleOrchestrator(api_key)
#     result = await orchestrator.process(input_text)
#     print(result)


if __name__ == "__main__":
    print("\n🔬 Lightweight Multi-Agent Test Framework")
    print("   Using Google Gemini 2.5 Flash (lowest cost)")
    print()
    
    asyncio.run(main())