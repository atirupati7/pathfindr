class SemanticAgent:
    def __init__(self, gemini):
        self.gemini = gemini
        self.name = "SemanticAgent"

    async def run(self, scene_data) -> str:
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