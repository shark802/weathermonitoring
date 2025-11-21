import logging
from django.db.models.signals import post_migrate
from django.dispatch import receiver
from .tasks import predict_rain_task

logger = logging.getLogger(__name__)

@receiver(post_migrate)
def start_ai_prediction_task(sender, **kwargs):
    """
    Triggers the Celery task to run the AI rain prediction after
    all database migrations have been applied.
    """
    logger.info("Django app ready. Triggering AI prediction task")
    predict_rain_task.delay()