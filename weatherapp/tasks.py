import os
from celery import Celery
from django.conf import settings
from django.db import connection
# ❗ Updated import: Removed fetch_weather_data_from_api as it's no longer used.
from .ai.predictor import predict_rain 
import numpy as np
import json
from datetime import datetime

# Define the expected sequence length for the time-series model
SEQUENCE_LENGTH = 6
FEATURE_COUNT = 5 # (temp, humid, wind, pressure, hour_of_day)

# Create a Celery instance
app = Celery('weather_app', broker=settings.CELERY_BROKER_URL)

@app.task(bind=True)
def predict_rain_task(self):
    """
    Celery task to perform asynchronous rain prediction using only database data.
    This task fetches the latest 6 data points to form the time series input.
    """
    print("AI prediction task started (Database Only Mode).")

    try:
        # 1. Fetch the last 6 data points from the database
        with connection.cursor() as cursor:
            # We must fetch the 4 features + date_time to calculate the hour_of_day feature
            query = f"""
                SELECT temperature, humidity, wind_speed, barometric_pressure, date_time
                FROM weather_reports
                ORDER BY date_time DESC
                LIMIT {SEQUENCE_LENGTH}
            """
            cursor.execute(query)
            # Data points are fetched newest-to-oldest
            data_points = cursor.fetchall()

        if len(data_points) < SEQUENCE_LENGTH:
            print(f"Not enough data points (found {len(data_points)}, need {SEQUENCE_LENGTH}) to run the time-series model. Skipping prediction.")
            return

        # 2. Process data: Reverse order (oldest to newest) and build the feature array
        data_points.reverse() # Reverse to get oldest-to-newest chronological order

        input_sequence = []
        for temp, humid, wind, pressure, date_time_obj in data_points:
            # Calculate the required 'hour_of_day' feature (0-23)
            hour_of_day = float(date_time_obj.hour)
            
            # Assemble the 5 features in the order expected by the predictor/model
            # [temperature, humidity, wind_speed, barometric_pressure, hour_of_day]
            input_sequence.append([
                float(temp),
                float(humid),
                float(wind),
                float(pressure),
                hour_of_day
            ])

        # Convert the list of lists (6, 5) into the required NumPy array
        input_features = np.array(input_sequence, dtype=np.float32)

        # 3. Call the prediction model
        # The predictor.py function now handles the scaling and reshaping internally
        rain_rate, duration, intensity = predict_rain(input_features)
        
        if rain_rate is None:
            print("Prediction failed inside the model function.")
            return

        # 4. Log prediction results to the database
        with connection.cursor() as cursor:
            # Note: Using NOW() to ensure the insertion time is recorded by the DB server
            cursor.execute("""
                INSERT INTO ai_predictions (predicted_rain, duration, intensity, created_at)
                VALUES (%s, %s, %s, NOW())
            """, [rain_rate, duration, intensity])

        print("--- Prediction Results ---")
        print(f"Predicted Rainfall: {rain_rate:.2f} mm")
        print(f"Estimated Duration: {duration:.2f} minutes")
        print(f"Rainfall Intensity: {intensity}")
        print("✅ Prediction results successfully inserted into the database.")

    except Exception as e:
        print(f"Prediction task failed: {str(e)}")
