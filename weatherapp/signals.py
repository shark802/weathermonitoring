from django.db.models.signals import post_migrate
from django.dispatch import receiver
from .tasks import predict_rain_task

@receiver(post_migrate)
def start_ai_prediction_task(sender, **kwargs):
    """
    Triggers the Celery task to run the AI rain prediction after
    all database migrations have been applied.
    """
    print("Django app is ready. Triggering AI prediction task...")
    predict_rain_task.delay()