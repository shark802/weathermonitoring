web: gunicorn weatheralert.wsgi --log-file - --workers 1 --threads 2 --timeout 120
worker: celery -A weatherapp worker --loglevel=info --concurrency=1
beat: celery -A weatherapp beat
predictor: python -m weatherapp.ai.predictor