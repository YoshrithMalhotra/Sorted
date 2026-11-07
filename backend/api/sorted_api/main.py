"""The Sorted API. Run it with:

    uvicorn sorted_api.main:app --env-file .env --reload
"""

import logging
import os
import secrets
from functools import lru_cache
from typing import Annotated

from fastapi import Depends, FastAPI, Header, HTTPException
from google import genai
from google.genai import types

from . import validate
from .contract import ParseRequest, ParseResponse
from .parser import GeminiParser, ParseFailed, Parser

logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"))

app = FastAPI(title="Sorted API", version="0.1.0")


@lru_cache
def get_parser() -> Parser:
    key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
    # The iOS app gives up after 15 seconds; GeminiParser keeps all attempts inside 14.
    client = genai.Client(api_key=key, http_options=types.HttpOptions(timeout=14_000)) if key else None
    return GeminiParser(
        client,
        model=os.environ.get("SORTED_MODEL", "gemini-3.8-flash"),
        fallback_models=os.environ.get("SORTED_FALLBACK_MODELS", "gemini-3.6-flash").replace(",", " ").split(),
        thinking_level=os.environ.get("SORTED_THINKING_LEVEL", "low"),
    )


def check_client_key(apikey: Annotated[str | None, Header()] = None) -> None:
    """Until sign-in lands, the app proves itself with the key in its build config.

    The app sends it as `apikey`. With SORTED_CLIENT_KEY unset, every caller is
    allowed, which is fine on a laptop and never fine on the internet.
    """
    expected = os.environ.get("SORTED_CLIENT_KEY")
    if expected and not (apikey and secrets.compare_digest(apikey, expected)):
        raise HTTPException(status_code=401, detail="invalid apikey")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/parse", response_model=ParseResponse, dependencies=[Depends(check_client_key)])
async def parse(request: ParseRequest, parser: Annotated[Parser, Depends(get_parser)]) -> ParseResponse:
    try:
        items = await parser.parse(request)
    except ParseFailed as error:
        logging.getLogger(__name__).warning("parse failed: %s", error)
        raise HTTPException(status_code=502, detail="parse failed") from error
    return ParseResponse(items=validate.clean(items, now=request.now))
