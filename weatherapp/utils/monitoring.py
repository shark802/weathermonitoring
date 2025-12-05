"""
Monitoring and alerting utilities for the weather alert system.
"""
import logging
import time
from functools import wraps
from django.core.cache import cache
from django.conf import settings

logger = logging.getLogger(__name__)


def track_performance(func_name):
    """
    Decorator to track function execution time and log performance metrics.
    
    Args:
        func_name: Name of the function being tracked
        
    Usage:
        @track_performance('get_weather_data')
        def get_weather_data():
            # ...
    """
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            start_time = time.time()
            try:
                result = func(*args, **kwargs)
                execution_time = time.time() - start_time
                
                # Log performance
                if execution_time > 1.0:  # Log slow queries (>1 second)
                    logger.warning(
                        "Slow operation detected: %s took %.2f seconds",
                        func_name,
                        execution_time
                    )
                else:
                    logger.debug(
                        "Operation completed: %s took %.2f seconds",
                        func_name,
                        execution_time
                    )
                
                # Store metrics in cache for monitoring dashboard
                try:
                    cache_key = f"metrics:{func_name}:execution_time"
                    # Store last 10 execution times (simplified - use proper time series in production)
                    cache.set(cache_key, execution_time, timeout=3600)
                except Exception:
                    pass  # Don't fail if metrics storage fails
                
                return result
            except Exception as e:
                execution_time = time.time() - start_time
                logger.error(
                    "Error in %s after %.2f seconds: %s",
                    func_name,
                    execution_time,
                    str(e),
                    exc_info=True
                )
                raise
        
        return wrapper
    return decorator


def log_database_query(query_type, table_name, execution_time=None, error=None):
    """
    Log database query metrics.
    
    Args:
        query_type: Type of query (SELECT, INSERT, UPDATE, DELETE)
        table_name: Name of the table being queried
        execution_time: Query execution time in seconds
        error: Error message if query failed
    """
    if error:
        logger.error(
            "Database query failed: %s on %s - %s",
            query_type,
            table_name,
            error
        )
    elif execution_time:
        if execution_time > 0.5:  # Log slow queries
            logger.warning(
                "Slow database query: %s on %s took %.2f seconds",
                query_type,
                table_name,
                execution_time
            )


def check_system_health():
    """
    Check system health metrics.
    
    Returns:
        dict: Health status with various metrics
    """
    health = {
        'status': 'healthy',
        'checks': {}
    }
    
    # Check cache connectivity
    try:
        cache.set('health_check', 'ok', timeout=10)
        cache_result = cache.get('health_check')
        health['checks']['cache'] = 'ok' if cache_result == 'ok' else 'degraded'
    except Exception as e:
        health['checks']['cache'] = f'error: {str(e)}'
        health['status'] = 'degraded'
    
    # Check database connectivity (would need to import connection)
    # This is a placeholder - implement actual DB health check
    
    return health

