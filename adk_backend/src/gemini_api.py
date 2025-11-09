import asyncio
import google.generativeai as genai


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

            return response.text
            
        except Exception as e:
            print(f"❌ API Error in {agent_name}: {e}")
            return f"Error: {str(e)}"