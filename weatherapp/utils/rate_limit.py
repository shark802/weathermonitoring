import time
import logging
from functools import wraps
from typing import Callable, Iterable, Optional

from django.core.cache import cache
from django.http import HttpRequest, JsonResponse

logger = logging.getLogger(__name__)


def _default_identifier(request: HttpRequest) -> str:
    """
    Determine a cache key fragment that identifies the client.

    Preference order:
    1. First IP listed in X-Forwarded-For (common for reverse proxies)
    2. REMOTE_ADDR provided by Django
    """
    forwarded_for = request.META.get("HTTP_X_FORWARDED_FOR")
    if forwarded_for:
        parts = [part.strip() for part in forwarded_for.split(",") if part.strip()]
        if parts:
            return parts[0]

    return request.META.get("REMOTE_ADDR") or "unknown"


def rate_limit(
    key_prefix: str,
    *,
    limit: int = 60,
    window: int = 60,
    methods: Optional[Iterable[str]] = None,
    identifier: Optional[Callable[[HttpRequest], str]] = None,
    error_message: Optional[str] = None,
):
    """
    Lightweight cache-based rate limiting decorator.

    Args:
        key_prefix: Identifier for the protected view/action.
        limit: Maximum number of requests within the window.
        window: Size of the sliding window in seconds.
        methods: Optional iterable of HTTP methods to enforce (defaults to all).
        identifier: Optional callable to compute a custom identifier.
        error_message: Custom 429 response message.
    """

    if limit <= 0:
        raise ValueError("limit must be greater than 0")
    if window <= 0:
        raise ValueError("window must be greater than 0")

    methods_set = {m.upper() for m in methods} if methods else None
    identifier = identifier or _default_identifier

    def decorator(view_func):
        @wraps(view_func)
        def _wrapped(request: HttpRequest, *args, **kwargs):
            if methods_set and request.method.upper() not in methods_set:
                return view_func(request, *args, **kwargs)

            try:
                client_id = identifier(request)
                cache_key = f"rl:{key_prefix}:{client_id}"
                now = time.time()

                try:
                    entry = cache.get(cache_key)
                    if entry:
                        count, start_time = entry
                    else:
                        count, start_time = 0, now
                except Exception as e:
                    # If cache fails, log and allow request through (graceful degradation)
                    logger.warning(f"Cache error in rate_limit for {key_prefix}: {e}")
                    return view_func(request, *args, **kwargs)

                elapsed = now - start_time
                if elapsed >= window:
                    count, start_time = 0, now
                    elapsed = 0

                if count >= limit:
                    retry_after = max(1, int(window - elapsed))
                    response = JsonResponse(
                        {
                            "detail": error_message
                            or "Too many requests. Please slow down and try again.",
                            "retry_after": retry_after,
                        },
                        status=429,
                    )
                    response["Retry-After"] = str(retry_after)
                    return response

                try:
                    cache.set(cache_key, (count + 1, start_time), timeout=window)
                except Exception as e:
                    # If cache set fails, log but allow request through
                    logger.warning(f"Cache set error in rate_limit for {key_prefix}: {e}")

                return view_func(request, *args, **kwargs)
            except Exception as e:
                # If identifier or any other operation fails, log and allow request through
                logger.error(f"Unexpected error in rate_limit decorator for {key_prefix}: {e}", exc_info=True)
                return view_func(request, *args, **kwargs)

        return _wrapped

    return decorator


