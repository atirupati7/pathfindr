import asyncio
import json

from src.utils import parse_llm_json


class AdaptivePromptAgent:
    """
    Adaptive meta-agent that chooses which sub-agents to call based on user prompt
    and context, then generates a prioritized response.
    """

    def __init__(self, gemini, agents: dict):
        """
        gemini: instance of LightweightGeminiService
        agents: dict of instantiated sub-agents
                e.g., {"hazard": HazardDetector(...),
                       "semantic": SemanticAgent(...),
                       "image": ImageSceneAgent(...)}
        """
        self.gemini = gemini
        self.agents = agents
        self.name = "AdaptivePromptAgent"

    async def respond(self, user_prompt: str, context: dict = None, image: str = 'files/IMG_9866.png') -> dict:
        """
        Decide which agents to call and in what order, then call them.
        context: optional scene information
        Returns structured output: {agent_outputs: {...}, final_answer: str}
        """
        context_summary = context or {}
        context_text = json.dumps(context_summary, indent=2)

        # Step 1: Ask Gemini to plan which agents to call
        planning_prompt = f"""
                            You are a coordinator AI. A user has issued the following prompt:
                            "{user_prompt}"

                            You have access to the following agents:
                            {list(self.agents.keys())}

                            Context (environmental/scene info):
                            {context_text}

                            Instructions:
                            1. Decide which agents are relevant for answering this prompt.
                            2. Specify the order to call them.
                            3. Use image model to capture a general vibe of the scene.

                            Return your plan as strict JSON in the format:
                            {{
                                "order": ["agent_name_1", "agent_name_2", ...]
                            }}
                            """
        
        plan_text = await self.gemini.generate(planning_prompt, self.name)
        plan = parse_llm_json(plan_text)

        # Step 2: Call agents in the planned order
        agent_outputs = {}
        for agent_name in plan["order"]:
            agent = self.agents.get(agent_name)

            if agent_name == "image summarizer":
                agent_outputs[agent_name] = await agent.run(image)
            else:
                agent_outputs[agent_name] = await agent.run(context)

        # Step 3: Optionally, ask Gemini to summarize/aggregate
        aggregation_prompt = f"""
                                You are an AI assistant. The user prompt was:
                                "{user_prompt}"

                                You have outputs from multiple agents:
                                {json.dumps(agent_outputs, indent=2)}

                                Combine these outputs into a single coherent answer. Focus on clarity, relevance, and prioritization.
                                Return only text suitable for speech output.
                                """
        final_answer = await self.gemini.generate(aggregation_prompt, self.name)

        return {"agent_outputs": agent_outputs, "final_answer": final_answer}