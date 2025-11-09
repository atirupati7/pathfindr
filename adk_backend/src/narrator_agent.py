class NarratorAgent:
    def __init__(self, gemini):
        self.gemini = gemini
        self.name = "PrioritizationAgent"

    async def run(self, hazard_text: str, semantic_text: str, image_text: str) -> str:
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


class PrioritizationAgent:
    def __init__(self, gemini):
        self.gemini = gemini
        self.name = "PrioritizationAgent"

    async def run(self, hazard_text: str, semantic_text: str, image_text: str) -> str:
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