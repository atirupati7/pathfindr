"""
Lightweight Multi-Agent Test for Google Gemini API
Tests agent coordination with minimal API calls and tracks usage/costs
"""

import os
import asyncio
import json
from dataclasses import dataclass
from typing import List, Dict, Any
from datetime import datetime
import google.generativeai as genai


# ============================================================================
# API USAGE TRACKER
# ============================================================================

@dataclass
class APICall:
    """Track individual API call"""
    agent_name: str
    model: str
    prompt_tokens: int
    response_tokens: int
    timestamp: float
    cost_usd: float


class UsageTracker:
    """Track and report API usage and costs"""
    
    # Pricing per 1M tokens (as of 2024)
    PRICING = {
        'gemini-2.5-flash': {
            'input': 0.075,   # $0.075 per 1M input tokens
            'output': 0.30,   # $0.30 per 1M output tokens
        },
        'gemini-2.5-pro': {
            'input': 1.25,
            'output': 5.00,
        }
    }
    
    def __init__(self):
        self.calls: List[APICall] = []
        self.start_time = datetime.now()
    
    def log_call(self, agent_name: str, model: str, prompt_tokens: int, response_tokens: int):
        """Log an API call"""
        pricing = self.PRICING.get(model, {'input': 0, 'output': 0})
        
        cost = (
            (prompt_tokens / 1_000_000) * pricing['input'] +
            (response_tokens / 1_000_000) * pricing['output']
        )
        
        call = APICall(
            agent_name=agent_name,
            model=model,
            prompt_tokens=prompt_tokens,
            response_tokens=response_tokens,
            timestamp=datetime.now().timestamp(),
            cost_usd=cost
        )
        
        self.calls.append(call)
    
    def report(self):
        """Generate usage report"""
        if not self.calls:
            print("\n⚠️  No API calls recorded")
            return
        
        total_prompt = sum(c.prompt_tokens for c in self.calls)
        total_response = sum(c.response_tokens for c in self.calls)
        total_tokens = total_prompt + total_response
        total_cost = sum(c.cost_usd for c in self.calls)
        
        print("\n" + "="*60)
        print("📊 API USAGE REPORT")
        print("="*60)
        print(f"⏱️  Duration: {(datetime.now() - self.start_time).total_seconds():.2f}s")
        print(f"📞 Total API Calls: {len(self.calls)}")
        print(f"📥 Input Tokens: {total_prompt:,}")
        print(f"📤 Output Tokens: {total_response:,}")
        print(f"📊 Total Tokens: {total_tokens:,}")
        print(f"💰 Estimated Cost: ${total_cost:.6f}")
        print("\n" + "-"*60)
        print("Per Agent Breakdown:")
        print("-"*60)
        
        agents = {}
        for call in self.calls:
            if call.agent_name not in agents:
                agents[call.agent_name] = {'calls': 0, 'cost': 0.0}
            agents[call.agent_name]['calls'] += 1
            agents[call.agent_name]['cost'] += call.cost_usd
        
        for agent, stats in agents.items():
            print(f"  {agent:20s} - {stats['calls']} calls, ${stats['cost']:.6f}")
        
        print("="*60 + "\n")


# ============================================================================
# LIGHTWEIGHT GEMINI SERVICE
# ============================================================================

class LightweightGeminiService:
    """Minimal Gemini API wrapper with usage tracking"""
    
    def __init__(self, api_key: str, tracker: UsageTracker):
        genai.configure(api_key=api_key)
        self.model_name = 'gemini-2.5-flash'  # Using flash for lower cost
        self.model = genai.GenerativeModel(self.model_name)
        self.tracker = tracker
    
    async def generate(self, prompt: str, agent_name: str) -> str:
        """Generate text and track usage"""
        try:
            response = await asyncio.to_thread(
                self.model.generate_content,
                prompt
            )
            
            # Estimate token counts (rough approximation)
            prompt_tokens = len(prompt.split()) * 1.3  # ~1.3 tokens per word
            response_tokens = len(response.text.split()) * 1.3
            
            self.tracker.log_call(
                agent_name=agent_name,
                model=self.model_name,
                prompt_tokens=int(prompt_tokens),
                response_tokens=int(response_tokens)
            )
            
            return response.text
            
        except Exception as e:
            print(f"❌ API Error in {agent_name}: {e}")
            return f"Error: {str(e)}"


# ============================================================================
# SIMPLE AGENTS
# ============================================================================

class AnalyzerAgent:
    """Analyzes input and extracts key information"""
    
    def __init__(self, gemini: LightweightGeminiService):
        self.gemini = gemini
        self.name = "AnalyzerAgent"
    
    async def analyze(self, text: str) -> str:
        """Analyze text input"""
        prompt = f"Analyze this text in 2-3 sentences: {text}"
        result = await self.gemini.generate(prompt, self.name)
        print(f"✓ {self.name} completed")
        return result


class SummarizerAgent:
    """Summarizes information concisely"""
    
    def __init__(self, gemini: LightweightGeminiService):
        self.gemini = gemini
        self.name = "SummarizerAgent"
    
    async def summarize(self, text: str) -> str:
        """Create brief summary"""
        prompt = f"Summarize in one sentence: {text}"
        result = await self.gemini.generate(prompt, self.name)
        print(f"✓ {self.name} completed")
        return result


class SynthesizerAgent:
    """Synthesizes multiple inputs into final output"""
    
    def __init__(self, gemini: LightweightGeminiService):
        self.gemini = gemini
        self.name = "SynthesizerAgent"
    
    async def synthesize(self, analysis: str, summary: str) -> str:
        """Combine analysis and summary"""
        prompt = f"Combine these insights into one coherent response:\nAnalysis: {analysis}\nSummary: {summary}"
        result = await self.gemini.generate(prompt, self.name)
        print(f"✓ {self.name} completed")
        return result


# ============================================================================
# LIGHTWEIGHT ORCHESTRATOR
# ============================================================================

class SimpleOrchestrator:
    """Coordinates agents with minimal overhead"""
    
    def __init__(self, api_key: str, tracker: UsageTracker):
        self.gemini = LightweightGeminiService(api_key, tracker)
        self.analyzer = AnalyzerAgent(self.gemini)
        self.summarizer = SummarizerAgent(self.gemini)
        self.synthesizer = SynthesizerAgent(self.gemini)
    
    async def process(self, input_text: str) -> str:
        """Process input through agent pipeline"""
        print("\n🚀 Starting multi-agent pipeline...")
        print("-" * 60)
        
        # Stage 1: Parallel analysis and summarization
        print("Stage 1: Running Analyzer and Summarizer (parallel)...")
        analysis, summary = await asyncio.gather(
            self.analyzer.analyze(input_text),
            self.summarizer.summarize(input_text)
        )
        
        # Stage 2: Synthesize results
        print("Stage 2: Running Synthesizer...")
        final_result = await self.synthesizer.synthesize(analysis, summary)
        
        print("-" * 60)
        print("✅ Pipeline complete\n")
        
        return final_result


# ============================================================================
# TEST SCENARIOS
# ============================================================================

async def test_scenario_1(orchestrator: SimpleOrchestrator):
    """Test 1: Simple text processing"""
    print("\n" + "="*60)
    print("TEST 1: Simple Text Analysis")
    print("="*60)
    
    input_text = "Artificial intelligence is transforming healthcare through machine learning models that can analyze medical images, predict patient outcomes, and assist in diagnosis."
    
    print(f"\n📝 Input: {input_text[:80]}...\n")
    
    result = await orchestrator.process(input_text)
    
    print("\n📋 Final Result:")
    print("-" * 60)
    print(result)
    print("-" * 60)


async def test_scenario_2(orchestrator: SimpleOrchestrator):
    """Test 2: Question processing"""
    print("\n" + "="*60)
    print("TEST 2: Question Analysis")
    print("="*60)
    
    input_text = "What are the main benefits of using renewable energy sources like solar and wind power?"
    
    print(f"\n📝 Input: {input_text}\n")
    
    result = await orchestrator.process(input_text)
    
    print("\n📋 Final Result:")
    print("-" * 60)
    print(result)
    print("-" * 60)


async def test_minimal(orchestrator: SimpleOrchestrator):
    """Minimal single-call test"""
    print("\n" + "="*60)
    print("MINIMAL TEST: Single Agent Call")
    print("="*60)
    
    input_text = "Test input for API usage tracking"
    
    print(f"\n📝 Input: {input_text}\n")
    print("Running single analyzer call...")
    
    result = await orchestrator.analyzer.analyze(input_text)
    
    print("\n📋 Result:")
    print("-" * 60)
    print(result)
    print("-" * 60)


# ============================================================================
# MAIN TEST RUNNER
# ============================================================================

async def main():
    """Run tests"""
    print("\n" + "="*60)
    print("🧪 LIGHTWEIGHT MULTI-AGENT ADK TEST")
    print("="*60)
    
    # Get API key
    api_key = os.getenv("GOOGLE_API_KEY")
    
    if not api_key:
        print("\n❌ ERROR: GOOGLE_API_KEY not found")
        print("\n📝 Set it with:")
        print("   export GOOGLE_API_KEY='your-api-key-here'")
        print("\n🔑 Get your key at: https://aistudio.google.com/app/apikey")
        return
    
    # Initialize
    tracker = UsageTracker()
    orchestrator = SimpleOrchestrator(api_key, tracker)
    
    # Choose test mode
    print("\n📋 Select test mode:")
    print("  1. Minimal test (1 API call) - cheapest")
    print("  2. Simple test (3 API calls) - full pipeline")
    print("  3. Two scenarios (6 API calls) - comprehensive")
    print("  4. All tests (7 API calls)")
    
    choice = input("\nEnter choice (1-4) or press Enter for minimal: ").strip() or "1"
    
    try:
        if choice == "1":
            await test_minimal(orchestrator)
        elif choice == "2":
            await test_scenario_1(orchestrator)
        elif choice == "3":
            await test_scenario_1(orchestrator)
            await test_scenario_2(orchestrator)
        elif choice == "4":
            await test_minimal(orchestrator)
            await test_scenario_1(orchestrator)
            await test_scenario_2(orchestrator)
        else:
            print("Invalid choice, running minimal test")
            await test_minimal(orchestrator)
        
        # Show usage report
        tracker.report()
        
        # Cost projection
        print("\n💡 COST PROJECTIONS:")
        print("-" * 60)
        total_cost = sum(c.cost_usd for c in tracker.calls)
        if total_cost > 0:
            calls_per_session = len(tracker.calls)
            print(f"  100 sessions like this: ${total_cost * 100:.4f}")
            print(f"  1,000 sessions: ${total_cost * 1000:.2f}")
            print(f"  10,000 sessions: ${total_cost * 10000:.2f}")
        print("="*60 + "\n")
        
    except KeyboardInterrupt:
        print("\n\n⚠️  Test interrupted by user")
        tracker.report()
    except Exception as e:
        print(f"\n\n❌ Error: {e}")
        tracker.report()


if __name__ == "__main__":
    print("\n🔬 Lightweight Multi-Agent Test Framework")
    print("   Using Google Gemini 2.5 Flash (lowest cost)")
    print()
    
    asyncio.run(main())