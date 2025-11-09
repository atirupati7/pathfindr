import os
import json
import uuid
import logging
import asyncio
from typing import Any, Dict, Optional

from flask import Flask, request, jsonify
from werkzeug.utils import secure_filename

# === ADK imports (adjust paths if needed) ===
from src.gemini_api import LightweightGeminiService
from src.hazard_agent import HazardDetector
from src.semantic_agent import SemanticAgent
from src.image_agent import ImageSceneAgent
from src.prompt_agent import AdaptivePromptAgent



# ADK ENTRYPOINT: this is what Flask calls

async def _run_adk_async(scene_data: Dict[str, Any],
                         image_path: Optional[str] = None) -> str:


    api_key = os.getenv("GOOGLE_API_KEY")
    if not api_key:
        raise RuntimeError("GOOGLE_API_KEY is not set")

    # 1. Gemini wrapper
    gemini = LightweightGeminiService(api_key=api_key)


    agents = {
        "hazard": HazardDetector(gemini),
        "semantic": SemanticAgent(gemini),
    }

    if image_path:
        # Name aligned with prompt_agent's image-handling logic
        agents["image summarizer"] = ImageSceneAgent(gemini)

    coordinator = AdaptivePromptAgent(gemini, agents)

    # High-level behavior instruction
    user_prompt = (
        "Provide prioritized, concise navigation guidance for a blind user based on "
        "the provided sensor data and, if available, the captured image. "
        "Focus on immediate hazards first, then overall scene context."
    )

    result = await coordinator.respond(
        user_prompt=user_prompt,
        context=scene_data,
        image=image_path or ""
    )

    final_answer = (result.get("final_answer") or "").strip()

    if not final_answer:
        # Fallback if something goes wrong upstream
        final_answer = (
            "I'm not fully sure about the surroundings. "
            "Please proceed cautiously and adjust your pace."
        )

    return final_answer


def run_adk(scene_data: Dict[str, Any],
            image_path: Optional[str] = None) -> str:
    """
    Sync wrapper so Flask (which runs in a normal sync context) can
    call the async ADK pipeline.
    """
    return asyncio.run(_run_adk_async(scene_data, image_path))


# =========================================================
# Flask App Factory
# =========================================================

def create_app() -> Flask:
    app = Flask(__name__)

    # Where to store uploaded images from Swift (if you send frames)
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

    # ---------------- Health Check ----------------

    @app.route("/health", methods=["GET"])
    def health() -> Any:
        return jsonify({"status": "ok", "service": "pathfinder-backend"}), 200

    # ---------------- Main Inference Endpoint ----------------

    @app.route("/api/v1/pathfinder", methods=["POST"])
    def pathfinder() -> Any:
        """
        Swift -> /api/v1/pathfinder

        Option A: application/json
            {
              "objects": [...],
              "free_space": {...},
              "other_sensor_data": {...}
            }

        Option B: multipart/form-data
            - metadata: JSON string with the same structure as above
            - image:   optional image file (single frame)

        Response:
            {
              "message": "<final narration from ADK>",
              "request_id": "<uuid>"
            }
        """

        request_id = str(uuid.uuid4())

        try:
            content_type = request.content_type or ""

            # ----- Case A: multipart (JSON + image) -----
            if "multipart/form-data" in content_type:
                metadata_raw = request.form.get("metadata")
                if not metadata_raw:
                    app.logger.warning(f"[{request_id}] Missing 'metadata' in multipart request")
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
                    app.logger.info(f"[{request_id}] No image provided in multipart request")

            # ----- Case B: pure JSON -----
            elif request.is_json:
                scene_data = request.get_json(silent=True) or {}
                image_path = None

                if not scene_data:
                    app.logger.warning(f"[{request_id}] Empty JSON body")
                    return jsonify({
                        "error": "Empty JSON body",
                        "request_id": request_id,
                    }), 400

            # ----- Unsupported content type -----
            else:
                app.logger.warning(f"[{request_id}] Unsupported Content-Type: {content_type}")
                return jsonify({
                    "error": "Unsupported Content-Type. "
                             "Use application/json or multipart/form-data.",
                    "request_id": request_id,
                }), 415

            # Log summary of input
            top_keys = ", ".join(list(scene_data.keys())[:10])
            app.logger.info(f"[{request_id}] Received scene data keys: {top_keys}")

            # ----- Call ADK coordinator -----
            final_message = run_adk(scene_data, image_path=image_path)

            app.logger.info(f"[{request_id}] ADK returned final message")

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


# Entrypoint

app = create_app()

if __name__ == "__main__":
    # From Swift (same Wi-Fi):
    #   POST -> http://<your-laptop-ip>:5000/api/v1/pathfinder
    app.run(host="0.0.0.0", port=5000, debug=True)
