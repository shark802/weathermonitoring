import logging
from django.apps import AppConfig

logger = logging.getLogger(__name__)


class WeatherappConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'weatherapp'

    def ready(self):
        from . import signals
        logger.info("WeatherAppConfig loaded signals")