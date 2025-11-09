import asyncio
import os

from src.gemini_api import LightweightGeminiService
from src.hazard_agent import HazardDetector
from src.image_agent import ImageSceneAgent
from src.narrator_agent import PrioritizationAgent, NarratorAgent
from src.semantic_agent import SemanticAgent
from src.prompt_agent import AdaptivePromptAgent


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
        hazard_task = asyncio.create_task(self.hazard_agent.run(scene_data))
        semantic_task = asyncio.create_task(self.semantic_agent.run(scene_data))
        image_task = asyncio.create_task(self.image_agent.run('files/IMG_9866.png'))

        hazard_text, semantic_text, image_text = await asyncio.gather(hazard_task, semantic_task, image_task)

        prioritized = await self.prioritization_agent.run(hazard_text, semantic_text, image_text)
        # narrated = await self.narrator_agent.narrate(prioritized)

        return {
            "hazards": hazard_text,
            "scene": semantic_text,
            "image": image_text,
            "final_output": prioritized
        }


async def prompt():

    # Initialize Gemini wrapper
    api_key = os.getenv("GOOGLE_API_KEY")
    gemini = LightweightGeminiService(api_key=api_key)

    user_prompt = "Give me a vibe of my surroundings, including the colors and objects."

    # Example input (from iPhone frontend)
    scene_data = {
        "objects": [
            {"label": "person", "distance_m": 1.2, "direction_deg": -10},
            {"label": "chair", "distance_m": 0.6, "direction_deg": 20},
            {"label": "wall", "distance_m": 1.5, "direction_deg": 0}
        ],
        "free_space": {"center_m": 0.8, "left_m": 1.5, "right_m": 2.0}
    }

    agents = {"hazard detector": HazardDetector(gemini),
              "semantic describer": SemanticAgent(gemini),
              "image describer": ImageSceneAgent(gemini)}
    
    coordinator = AdaptivePromptAgent(gemini, agents)
    output = await coordinator.respond(user_prompt, scene_data)
    print(output)


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
    print("\n🗣 Individual agent outputs:\n", output)
    # print("\n🗣 Final Narration:\n", output["final_output"])


if __name__ == "__main__":
    print("\n🔬 Lightweight Multi-Agent Test Framework")
    print("   Using Google Gemini 2.5 Flash (lowest cost)")
    print()
    
    asyncio.run(prompt())