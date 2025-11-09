class HazardDetector:
    def __init__(self, gemini):
        self.gemini = gemini
        self.name = "HazardDetector"

    async def run(self, scene_data) -> str:
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