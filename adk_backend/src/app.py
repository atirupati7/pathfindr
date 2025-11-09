
import os
import uuid
import logging
import asyncio
from typing import Any, Dict

from flask import Flask, request, jsonify

# ADK pieces
from src.gemini_api import LightweightGeminiService
from main import CentralCoordinator  # uses agents from src/

# Create ADK coordinator

def create_coordinator() -> CentralCoordinator:
    api_key = os.getenv("GOOGLE_API_KEY")
    if not api_key:
        raise RuntimeError("GOOGLE_API_KEY is not set in environment")

    gemini = LightweightGeminiService(api_key=api_key)
    return CentralCoordinator(gemini)


coordinator = None  # will be initialized in create_app()


# Flask app factory

def create_app() -> Flask:
    global coordinator

    app = Flask(__name__)

    # Logging setup
    app.logger.setLevel(logging.INFO)
    handler = logging.StreamHandler()
    formatter = logging.Formatter("[%(asctime)s] [%(levelname)s] %(message)s")
    handler.setFormatter(formatter)
    if not app.logger.handlers:
        app.logger.addHandler(handler)

    # Initialize ADK coordinator once
    try:
        coordinator = create_coordinator()
        app.logger.info("CentralCoordinator initialized successfully")
    except Exception as e:
        app.logger.error(f"Failed to initialize CentralCoordinator: {e}")

    # Health check
    @app.route("/health", methods=["GET"])
    def health() -> Any:
        status = "ok" if coordinator is not None else "error"
        return jsonify({"status": status, "service": "pathfinder-backend"}), (
            200 if status == "ok" else 500
        )

    # Main API endpoint
    @app.route("/api/v1/pathfinder", methods=["POST"])
    def pathfinder() -> Any:

        request_id = str(uuid.uuid4())

        if coordinator is None:
            app.logger.error(f"[{request_id}] CentralCoordinator not initialized")
            return (
                jsonify(
                    {
                        "error": "Backend not initialized",
                        "request_id": request_id,
                    }
                ),
                500,
            )

        if not request.is_json:
            app.logger.warning(
                f"[{request_id}] Invalid Content-Type: {request.content_type}"
            )
            return (
                jsonify(
                    {
                        "error": "Content-Type must be application/json",
                        "request_id": request_id,
                    }
                ),
                400,
            )

        scene_data: Dict[str, Any] = request.get_json(silent=True) or {}
        if not scene_data:
            app.logger.warning(f"[{request_id}] Empty or invalid JSON body")
            return (
                jsonify(
                    {
                        "error": "Empty or invalid JSON body",
                        "request_id": request_id,
                    }
                ),
                400,
            )

        # Log a compact summary
        top_keys = ", ".join(list(scene_data.keys())[:10])
        app.logger.info(
            f"[{request_id}] Received scene data with keys: {top_keys}"
        )

        try:
            # CentralCoordinator.process_scene is async → bridge via asyncio.run
            result = asyncio.run(coordinator.process_scene(scene_data))


            final_message = (result.get("final_output") or "").strip()
            if not final_message:
                final_message = (
                    "I'm unable to clearly interpret the scene. "
                    "Please proceed with caution."
                )

            response_body = {
                "message": final_message,
                "agent_outputs": {
                    "hazards": result.get("hazards", ""),
                    "scene": result.get("scene", ""),
                    "image": result.get("image", ""),
                },
                "request_id": request_id,
            }

            app.logger.info(f"[{request_id}] Successfully generated response")
            return jsonify(response_body), 200

        except Exception as e:
            app.logger.exception(
                f"[{request_id}] Unhandled exception in /api/v1/pathfinder: {e}"
            )
            return (
                jsonify(
                    {
                        "error": "Internal server error",
                        "request_id": request_id,
                    }
                ),
                500,
            )

    return app


# Entrypoint

app = create_app()

if __name__ == "__main__":
    # Run locally:
    #   export GOOGLE_API_KEY="your_key_here"
    #   python app.py
    #
    # Swift calls:
    #   POST http://<your-ip>:5000/api/v1/pathfinder
    app.run(host="0.0.0.0", port=5000, debug=True)
