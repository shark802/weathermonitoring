web: gunicorn weatheralert.wsgi --log-file -
worker: celery -A weatherapp worker --loglevel=info
beat: celery -A weatherapp beat