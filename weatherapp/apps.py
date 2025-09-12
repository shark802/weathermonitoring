from django.apps import AppConfig


class WeatherappConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'weatherapp'

    def ready(self):
        from . import signals
        print("WeatherAppConfig is ready to load signals...")