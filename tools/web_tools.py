#!/usr/bin/env python3
"""
SearXNG-only web tools for WHOX.

Supported search categories: general, images, videos, news.
"""

import asyncio
import json
import logging
import os
import re
from html import unescape
from typing import Any, Dict, List
from urllib.parse import urlparse

import httpx

from tools.registry import registry
from tools.url_safety import is_safe_url
from tools.website_policy import check_website_access

logger = logging.getLogger(__name__)

_WEB_SEARCH_CATEGORIES = {"general", "images", "videos", "news"}
_IMAGE_EXTENSIONS = (
    ".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp", ".svg", ".avif", ".heic", ".tif", ".tiff"
)


def _env_float(name: str, default: float) -> float:
    raw = (os.getenv(name) or "").strip()
    if not raw:
        return default
    try:
        value = float(raw)
        if value <= 0:
            return default
        return value
    except Exception:
        return default


_SEARXNG_SEARCH_TIMEOUT_SECONDS = _env_float("WHOX_SEARXNG_SEARCH_TIMEOUT_SECONDS", 4.0)
_WEB_EXTRACT_TIMEOUT_SECONDS = _env_float("WHOX_WEB_EXTRACT_TIMEOUT_SECONDS", 20.0)


def _get_searxng_base_url() -> str:
    return (
        os.getenv("SEARXNG_API_URL", "").strip()
        or os.getenv("SEARXNG_BASE_URL", "").strip()
        or os.getenv("SEARXNG_URL", "").strip()
        or "http://127.0.0.1:18080"
    ).rstrip("/")


def _normalize_search_category(category: str) -> str:
    value = (category or "general").strip().lower()
    return value if value in _WEB_SEARCH_CATEGORIES else "general"


def _looks_like_image_url(url: str) -> bool:
    lower = (url or "").lower()
    if not (lower.startswith("http://") or lower.startswith("https://")):
        return False
    parsed = urlparse(lower)
    if any(parsed.path.endswith(ext) for ext in _IMAGE_EXTENSIONS):
        return True
    return any(token in parsed.query for token in ("format=jpg", "format=jpeg", "format=png", "format=webp", "image"))


def _extract_image_candidate(item: Dict[str, Any]) -> str:
    for key in ("img_src", "thumbnail_src", "thumbnail", "image", "image_url", "url"):
        value = item.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""


def _searxng_search(query: str, category: str, limit: int, pageno: int = 1) -> Dict[str, Any]:
    base_url = _get_searxng_base_url()
    endpoint = base_url if base_url.endswith("/search") else f"{base_url}/search"
    params = {
        "q": query,
        "format": "json",
        "categories": category,
        "pageno": max(1, int(pageno or 1)),
    }

    headers = {
        "User-Agent": "WHOX/1.0 (+local searxng)",
        "Accept": "application/json,text/html,*/*",
        "X-Forwarded-For": "127.0.0.1",
        "X-Real-IP": "127.0.0.1",
    }
    with httpx.Client(timeout=_SEARXNG_SEARCH_TIMEOUT_SECONDS, follow_redirects=True, headers=headers) as client:
        resp = client.get(endpoint, params=params)
        resp.raise_for_status()
        payload = resp.json()

    rows = payload.get("results") if isinstance(payload, dict) else []
    rows = rows if isinstance(rows, list) else []
    rows = rows[: max(1, min(int(limit or 5), 20))]

    web_rows: List[Dict[str, Any]] = []
    for idx, item in enumerate(rows):
        if not isinstance(item, dict):
            continue
        web_rows.append(
            {
                "title": item.get("title") or "",
                "url": item.get("url") or "",
                "description": item.get("content") or item.get("description") or "",
                "position": idx + 1,
                "img_src": item.get("img_src") or item.get("thumbnail_src") or item.get("thumbnail"),
                "thumbnail": item.get("thumbnail_src") or item.get("thumbnail"),
            }
        )
    return {"success": True, "data": {"web": web_rows}, "backend": "searxng", "category": category}


def _shape_image_search_results(web_results: List[Dict[str, Any]], limit: int) -> List[Dict[str, Any]]:
    images: List[Dict[str, Any]] = []
    seen: set[str] = set()
    max_results = max(1, min(int(limit or 5), 20))

    for item in web_results:
        src = _extract_image_candidate(item)
        if not src or src in seen:
            continue
        if not _looks_like_image_url(src):
            continue
        seen.add(src)
        images.append(
            {
                "src": src,
                "source_page": str(item.get("url") or "").strip(),
                "title": str(item.get("title") or "").strip(),
                "position": len(images) + 1,
            }
        )
        if len(images) >= max_results:
            break
    return images


def _paginate_rows(rows: List[Dict[str, Any]], per_page: int, pageno: int) -> List[Dict[str, Any]]:
    page = max(1, int(pageno or 1))
    size = max(1, min(int(per_page or 5), 20))
    start = (page - 1) * size
    end = start + size
    return rows[start:end]


def web_search_tool(query: str, limit: int = 5, category: str = "general", pageno: int = 1) -> str:
    try:
        normalized_category = _normalize_search_category(category)
        page = max(1, int(pageno or 1))
        per_page = max(1, min(int(limit or 15), 20))
        response = _searxng_search(query=query, category=normalized_category, limit=per_page, pageno=page)
        web_results = (response.get("data") or {}).get("web") or []

        if normalized_category == "images":
            images = _shape_image_search_results(web_results, limit=per_page)
        response_data = {
            "success": True,
            "category": "images",
            "search_backend": "searxng",
            "pageno": page,
            "per_page": per_page,
            "data": {
                    "image_src_only": True,
                    "images": images,
                    "web": [
                        {
                            "title": item.get("title", "") or f"Image {idx + 1}",
                            "url": item["src"],
                            "description": "Direct image source URL",
                            "position": idx + 1,
                        }
                        for idx, item in enumerate(images)
                    ],
                },
            }
        return json.dumps(response_data, indent=2, ensure_ascii=False)

        page_web = _paginate_rows(web_results, per_page, page)
        response_data = {
            "success": True,
            "category": normalized_category,
            "search_backend": "searxng",
            "pageno": page,
            "per_page": per_page,
            "data": {"web": page_web},
        }
        return json.dumps(response_data, indent=2, ensure_ascii=False)
    except Exception as e:
        return json.dumps({"success": False, "error": f"Error searching web: {str(e)}"}, ensure_ascii=False)


def _html_to_text(html: str) -> str:
    cleaned = re.sub(r"(?is)<script.*?>.*?</script>", " ", html)
    cleaned = re.sub(r"(?is)<style.*?>.*?</style>", " ", cleaned)
    cleaned = re.sub(r"(?is)<[^>]+>", " ", cleaned)
    cleaned = unescape(cleaned)
    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    return cleaned


async def web_extract_tool(urls: List[str], format: str = None, use_llm_processing: bool = False) -> str:
    del format
    del use_llm_processing

    documents: List[Dict[str, Any]] = []
    for raw_url in (urls or [])[:5]:
        url = str(raw_url or "").strip()
        if not url:
            continue
        if not is_safe_url(url):
            continue
        allowed, reason = check_website_access(url)
        if not allowed:
            documents.append(
                {
                    "url": url,
                    "content": "",
                    "error": reason or "blocked by policy",
                    "metadata": {"sourceURL": url},
                }
            )
            continue
        try:
            async with httpx.AsyncClient(timeout=_WEB_EXTRACT_TIMEOUT_SECONDS, follow_redirects=True) as client:
                resp = await client.get(url)
                resp.raise_for_status()
            text = _html_to_text(resp.text)
            if len(text) > 50000:
                text = text[:50000]
            documents.append(
                {
                    "url": url,
                    "content": text,
                    "raw_content": text,
                    "metadata": {"sourceURL": url, "status_code": resp.status_code},
                }
            )
        except Exception as exc:
            documents.append(
                {
                    "url": url,
                    "content": "",
                    "error": str(exc),
                    "metadata": {"sourceURL": url},
                }
            )
    return json.dumps({"success": True, "data": {"documents": documents}}, ensure_ascii=False)


async def web_crawl_tool(url: str, instruction: str, max_pages: int = 3, max_depth: int = 1) -> str:
    del url
    del instruction
    del max_pages
    del max_depth
    return json.dumps(
        {"success": False, "error": "web_crawl is disabled in this WHOX build. Use web_search + web_extract."},
        ensure_ascii=False,
    )


def check_web_api_key() -> bool:
    return bool(_get_searxng_base_url())


def check_auxiliary_model() -> bool:
    return False


def _web_requires_env() -> list[str]:
    return ["SEARXNG_API_URL"]


WEB_SEARCH_SCHEMA = {
    "name": "web_search",
    "description": "Search the web with SearXNG. Supported categories: general, images, videos, news. Returns 15 results per page by default. For category=images, returns image src links only.",
    "parameters": {
        "type": "object",
        "properties": {
            "query": {"type": "string", "description": "The search query to look up on the web"},
            "category": {
                "type": "string",
                "enum": ["general", "images", "videos", "news"],
                "description": "Search category. Use images to return image source links.",
            },
            "pageno": {"type": "integer", "minimum": 1, "default": 1, "description": "1-based page number."},
        },
        "required": ["query", "category"],
    },
}

WEB_EXTRACT_SCHEMA = {
    "name": "web_extract",
    "description": "Extract readable text content from web page URLs.",
    "parameters": {
        "type": "object",
        "properties": {
            "urls": {
                "type": "array",
                "items": {"type": "string"},
                "description": "List of URLs to extract content from (max 5 URLs per call)",
                "maxItems": 5,
            }
        },
        "required": ["urls"],
    },
}

registry.register(
    name="web_search",
    toolset="web",
    schema=WEB_SEARCH_SCHEMA,
    handler=lambda args, **kw: web_search_tool(
        args.get("query", ""),
        limit=5,
        category=args.get("category", "general"),
        pageno=args.get("pageno", 1),
    ),
    check_fn=check_web_api_key,
    requires_env=_web_requires_env(),
    emoji="🔍",
)

registry.register(
    name="web_extract",
    toolset="web",
    schema=WEB_EXTRACT_SCHEMA,
    handler=lambda args, **kw: web_extract_tool(
        args.get("urls", [])[:5] if isinstance(args.get("urls"), list) else [], "markdown"
    ),
    check_fn=check_web_api_key,
    requires_env=_web_requires_env(),
    is_async=True,
    emoji="📄",
)
