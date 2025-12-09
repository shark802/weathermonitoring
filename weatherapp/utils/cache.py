"""
Caching utilities for frequently accessed data.
Uses Redis when available, falls back to local memory cache.
"""
from functools import wraps
from django.core.cache import cache
from django.conf import settings
import hashlib
import json
import logging

logger = logging.getLogger(__name__)


def safe_cache_get(key, default=None):
    """
    Safely get a value from cache, returning default if cache is unavailable.
    
    Args:
        key: Cache key
        default: Default value to return if cache fails or key not found
        
    Returns:
        Cached value or default
    """
    try:
        return cache.get(key, default)
    except Exception as e:
        logger.warning("Cache get error for key %s: %s", key, e)
        return default


def safe_cache_set(key, value, timeout=None):
    """
    Safely set a value in cache, logging warning if cache is unavailable.
    
    Args:
        key: Cache key
        value: Value to cache
        timeout: Cache timeout in seconds
    """
    try:
        cache.set(key, value, timeout)
    except Exception as e:
        logger.warning("Cache set error for key %s: %s", key, e)

# Cache timeouts (in seconds)
CACHE_TIMEOUTS = {
    'weather_data': 60,  # 1 minute - weather data updates frequently
    'dashboard_data': 30,  # 30 seconds - dashboard auto-refreshes
    'sensor_list': 300,  # 5 minutes - sensor list changes infrequently
    'barangay_data': 3600,  # 1 hour - barangay data is static
    'user_list': 300,  # 5 minutes - user list changes infrequently
    'admin_list': 300,  # 5 minutes - admin list changes infrequently
    'reports': 180,  # 3 minutes - reports can be cached briefly
    'alerts': 30,  # 30 seconds - alerts need to be relatively fresh
}


def get_cache_key(prefix, *args, **kwargs):
    """
    Generate a consistent cache key from prefix and arguments.
    
    Args:
        prefix: Cache key prefix (e.g., 'weather_data')
        *args: Positional arguments to include in key
        **kwargs: Keyword arguments to include in key
        
    Returns:
        str: Cache key
    """
    key_parts = [prefix]
    
    # Add args
    for arg in args:
        if arg is not None:
            key_parts.append(str(arg))
    
    # Add kwargs (sorted for consistency)
    for k, v in sorted(kwargs.items()):
        if v is not None:
            key_parts.append(f"{k}:{v}")
    
    # Create hash for long keys
    key_str = ":".join(key_parts)
    if len(key_str) > 200:
        key_hash = hashlib.md5(key_str.encode()).hexdigest()
        return f"{prefix}:{key_hash}"
    
    return key_str


def cached_result(cache_type, timeout=None):
    """
    Decorator to cache function results.
    
    Args:
        cache_type: Type of cache (used to determine timeout)
        timeout: Override timeout (in seconds). If None, uses CACHE_TIMEOUTS
        
    Usage:
        @cached_result('weather_data')
        def get_weather_data(sensor_id):
            # ... expensive operation
            return data
    """
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            # Generate cache key
            cache_key = get_cache_key(
                f"cache:{cache_type}:{func.__name__}",
                *args,
                **kwargs
            )
            
            # Get timeout
            cache_timeout = timeout or CACHE_TIMEOUTS.get(cache_type, 60)
            
            # Try to get from cache
            cached_value = safe_cache_get(cache_key)
            if cached_value is not None:
                logger.debug("Cache hit for %s", cache_key)
                return cached_value
            
            # Cache miss - execute function
            logger.debug("Cache miss for %s", cache_key)
            result = func(*args, **kwargs)
            
            # Store in cache
            safe_cache_set(cache_key, result, cache_timeout)
            
            return result
        
        return wrapper
    return decorator


def invalidate_cache_pattern(pattern):
    """
    Invalidate all cache keys matching a pattern.
    Note: This is a simplified version. For production, consider using
    Redis SCAN or maintaining a registry of cache keys.
    
    Args:
        pattern: Pattern to match (e.g., 'cache:weather_data:*')
    """
    # This is a placeholder - full implementation would require
    # maintaining a key registry or using Redis SCAN
    logger.info("Cache invalidation requested for pattern: %s", pattern)
    # In production, implement proper cache invalidation


def cache_weather_data(sensor_id=None, timeout=None):
    """
    Cache weather data with appropriate timeout.
    
    Args:
        sensor_id: Optional sensor ID to include in cache key
        timeout: Override default timeout
        
    Returns:
        Decorator function
    """
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            cache_key = get_cache_key(
                'weather_data',
                sensor_id=sensor_id,
                **kwargs
            )
            cache_timeout = timeout or CACHE_TIMEOUTS['weather_data']
            
            cached = safe_cache_get(cache_key)
            if cached is not None:
                return cached
            
            result = func(*args, **kwargs)
            safe_cache_set(cache_key, result, cache_timeout)
            return result
        
        return wrapper
    return decorator

