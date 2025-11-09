import asyncio
from vertexai.preview.vision_models import Image
from PIL import Image as PILImage

class ImageSceneAgent:
    """
    Uses Gemini 2.0 Flash Lite (via LightweightGeminiService) for visual scene understanding.
    Works with local image files (converted to PIL format).
    """

    def __init__(self, gemini):
        self.gemini = gemini
        self.name = "ImageSceneAgent"

    async def run(self, image_path: str, context: str = "") -> str:
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