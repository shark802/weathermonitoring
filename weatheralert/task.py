# weather_app/celery.py
import os
from celery import Celery
from celery.schedules import crontab

# Set the default Django settings module for the 'celery' program.
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'weather_app.settings')

app = Celery('weather_app')

# Using a string here means the worker doesn't have to serialize
# the configuration object to child processes.
# - namespace='CELERY' means all celery-related configuration keys
#   should have a `CELERY_` prefix.
app.config_from_object('django.conf:settings', namespace='CELERY')

# Load task modules from all registered Django app configs.
app.autodiscover_tasks()

# ❗ New: Define a periodic task schedule
# This will run the 'predict_rain_task' every 10 minutes.
app.conf.beat_schedule = {
    'run-prediction-every-10-minutes': {
        'task': 'weather_app.tasks.predict_rain_task',
        'schedule': crontab(minute='*/10'),
    },
}

@app.task(bind=True)
def debug_task(self):
    print(f'Request: {self.request!r}')
