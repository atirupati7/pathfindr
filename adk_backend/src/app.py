import os
import json
import uuid
import logging
import asyncio
from typing import Any, Dict, Optional

from flask import Flask, request, jsonify
from werkzeug.utils import secure_filename

# ==== ADK imports ====
from gemini_api import LightweightGeminiService
from hazard_agent import HazardDetector
from semantic_agent import SemanticAgent
from image_agent import ImageSceneAgent
from prompt_agent import AdaptivePromptAgent


# ADK ENTRYPOINT

async def _run_adk_async(
    scene_data: Dict[str, Any],
    image_path: Optional[str] = None,
) -> str:
    """
    Async ADK pipeline:
    - Initializes Gemini service + agents
    - Uses AdaptivePromptAgent to coordinate them
    - Returns final narration string
    """

    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        raise RuntimeError("GEMINI_API_KEY is not set")

    # 1) Set up Gemini wrapper
    gemini = LightweightGeminiService(api_key=api_key)

    # 2) Instantiate agents
    agents = {
        "hazard": HazardDetector(gemini),
        "semantic": SemanticAgent(gemini),
    }

    # Only include image agent if we actually have an image
    if image_path:
        agents["image summarizer"] = ImageSceneAgent(gemini)

    # 3) Coordinator / meta-agent
    coordinator = AdaptivePromptAgent(gemini, agents)

    # 4) High-level instruction to the system
    user_prompt = (
        "Provide prioritized, concise navigation guidance for a blind user based on "
        "the provided sensor data and, if available, the scene image."
    )

    # AdaptivePromptAgent handles:
    # - planning which agents to call
    # - running them in order
    # - aggregating into a final answer suitable for speech
    result = await coordinator.respond(
        user_prompt=user_prompt,
        context=scene_data,
        image=image_path or ""
    )

    # result is expected: {"agent_outputs": {...}, "final_answer": str}
    final_answer = result.get("final_answer", "").strip()
    if not final_answer:
        final_answer = "I'm unable to interpret the scene clearly. Please proceed with caution."

    return final_answer


def run_adk(scene_data: Dict[str, Any], image_path: Optional[str] = None) -> str:

    return asyncio.run(_run_adk_async(scene_data, image_path))


# FLASK APP FACTORY

def create_app() -> Flask:
    app = Flask(__name__)

    # Configure uploads (for incoming images from Swift)
    upload_dir = os.path.join(os.path.dirname(__file__), "uploads")
    os.makedirs(upload_dir, exist_ok=True)
    app.config["UPLOAD_FOLDER"] = upload_dir

    # Logging
    app.logger.setLevel(logging.INFO)
    handler = logging.StreamHandler()
    formatter = logging.Formatter("[%(asctime)s] [%(levelname)s] %(message)s")
    handler.setFormatter(formatter)
    if not app.logger.handlers:
        app.logger.addHandler(handler)

    # ---------- Health Check ----------

    @app.route("/health", methods=["GET"])
    def health() -> Any:
        return jsonify({"status": "ok", "service": "pathfinder-backend"}), 200

    # ---------- Main API: Swift -> ADK ----------

    @app.route("/api/v1/pathfinder", methods=["POST"])
    def pathfinder() -> Any:

        request_id = str(uuid.uuid4())

        try:
            # --- Case A: multipart/form-data (JSON + image file) ---
            if request.content_type and "multipart/form-data" in request.content_type:
                metadata_raw = request.form.get("metadata")
                if not metadata_raw:
                    app.logger.warning(f"[{request_id}] Missing 'metadata' field in multipart request")
                    return jsonify({
                        "error": "Missing 'metadata' field in multipart request",
                        "request_id": request_id,
                    }), 400

                try:
                    scene_data = json.loads(metadata_raw)
                except json.JSONDecodeError:
                    app.logger.warning(f"[{request_id}] Invalid JSON in 'metadata'")
                    return jsonify({
                        "error": "Invalid JSON in 'metadata'",
                        "request_id": request_id,
                    }), 400

                image_file = request.files.get("image")
                image_path = None

                if image_file and image_file.filename:
                    filename = secure_filename(f"{request_id}_{image_file.filename}")
                    image_path = os.path.join(app.config["UPLOAD_FOLDER"], filename)
                    image_file.save(image_path)
                    app.logger.info(f"[{request_id}] Saved image to {image_path}")
                else:
                    app.logger.info(f"[{request_id}] No image file provided")

            # --- Case B: application/json only ---
            elif request.is_json:
                scene_data = request.get_json(silent=True) or {}
                image_path = None
                if not scene_data:
                    app.logger.warning(f"[{request_id}] Empty JSON body")
                    return jsonify({
                        "error": "Empty JSON body",
                        "request_id": request_id,
                    }), 400

            else:
                app.logger.warning(f"[{request_id}] Unsupported Content-Type: {request.content_type}")
                return jsonify({
                    "error": "Unsupported Content-Type. Use application/json or multipart/form-data.",
                    "request_id": request_id,
                }), 415

            # Log keys for sanity
            top_keys = ", ".join(list(scene_data.keys())[:10])
            app.logger.info(f"[{request_id}] Received scene data keys: {top_keys}")

            # --- Call ADK ---
            final_message = run_adk(scene_data, image_path=image_path)

            app.logger.info(f"[{request_id}] ADK returned message")

            return jsonify({
                "message": final_message,
                "request_id": request_id,
            }), 200

        except Exception as e:
            app.logger.exception(f"[{request_id}] Unhandled exception: {e}")
            return jsonify({
                "error": "Internal server error",
                "request_id": request_id,
            }), 500

    return app


# WSGI / Dev Entrypoint

app = create_app()

if __name__ == "__main__":
    # On device / Swift:
    #   POST -> http://<your-ip>:5000/api/v1/pathfinder
    app.run(host="0.0.0.0", port=5000, debug=True)
