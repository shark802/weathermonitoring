# Memory Optimization for Heroku Deployment

## Problem
Heroku free tier has a 512MB memory limit. The application was using 557MB (108.8%), causing R14 errors and 500 server errors.

## Root Causes
1. **TensorFlow model loaded at import time** - Models can consume 100-300MB+ of memory
2. **Multiple Gunicorn workers** - Each worker loads the entire Django app + TensorFlow
3. **Celery workers** - Additional processes loading models
4. **No memory limits on TensorFlow** - TensorFlow allocates memory aggressively

## Solutions Implemented

### 1. Reduced Gunicorn Workers
**File**: `Procfile`
- Changed from default (4 workers) to **1 worker with 2 threads**
- Reduces memory from ~4x to 1x Django app memory

```bash
web: gunicorn weatheralert.wsgi --log-file - --workers 1 --threads 2 --timeout 120
```

### 2. Reduced Celery Concurrency
**File**: `Procfile`
- Limited Celery worker to **1 concurrent task**
- Prevents multiple model instances in memory

```bash
worker: celery -A weatherapp worker --loglevel=info --concurrency=1
```

### 3. TensorFlow Memory Configuration
**File**: `weatherapp/ai/predictor.py`
- Configured TensorFlow to use minimal memory
- Limited CPU parallelism
- Enabled memory growth limits

```python
# Limit CPU memory usage
tf.config.threading.set_inter_op_parallelism_threads(1)
tf.config.threading.set_intra_op_parallelism_threads(1)
```

### 4. Lazy Model Loading
**File**: `weatherapp/ai/predictor.py`
- Model is now loaded **only when needed** (on first prediction)
- Prevents model from loading in web process if not used
- Thread-safe implementation with locks

**Before**: Model loaded at import time (always in memory)
**After**: Model loaded on-demand (only when `predict_rain()` is called)

### 5. Optimized Model Predictions
- Set `batch_size=1` for predictions
- Disabled verbose output
- Used minimal memory footprint

## Expected Memory Usage

| Component | Before | After |
|-----------|--------|-------|
| Django App (1 worker) | ~150MB | ~150MB |
| TensorFlow Model | ~200MB (always) | ~200MB (on-demand) |
| Celery Worker | ~150MB | ~150MB |
| Other processes | ~57MB | ~57MB |
| **Total** | **~557MB** | **~407MB** (when model loaded) |

**Note**: Model is only loaded in the `predictor` process, not in the web process.

## Process Architecture

```
Heroku Dynos:
├── web (1 worker, 2 threads)     ~150MB (no model)
├── worker (Celery, concurrency=1) ~150MB (no model)
├── beat (Celery scheduler)        ~50MB (no model)
└── predictor (AI service)         ~350MB (with model)
```

## Monitoring

Check memory usage:
```bash
heroku logs --tail | grep "mem="
```

Expected: Memory should stay under 512MB per dyno.

## Additional Optimizations (If Still Needed)

1. **Upgrade Heroku Plan**: Consider Standard-1X (512MB) or Standard-2X (1GB)
2. **Model Quantization**: Convert model to INT8 to reduce size by 4x
3. **Model Pruning**: Remove unnecessary weights
4. **Separate Dynos**: Run predictor on separate dyno type
5. **Use TensorFlow Lite**: Lighter-weight model format

## Verification

After deployment, verify:
1. Memory usage stays under 512MB
2. No R14 errors in logs
3. Predictions still work correctly
4. Web requests respond normally

## Rollback

If issues occur, revert `Procfile`:
```bash
web: gunicorn weatheralert.wsgi --log-file -
worker: celery -A weatherapp worker --loglevel=info
```

