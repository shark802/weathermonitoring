
import os
import requests
import certifi
from celery import Celery
from django.conf import settings
from django.db import connection
from .ai.predictor import predict_rain, get_rain_intensity, fetch_weather_data_from_api
import numpy as np
import time
import json
from datetime import datetime

# Create a Celery instance
app = Celery('weather_app', broker=settings.CELERY_BROKER_URL)

@app.task(bind=True)
def predict_rain_task(self):
    """
    Celery task to perform asynchronous rain prediction.
    This task now fetches the latest 6 data points for a time series prediction.
    """
    print("AI prediction task started.")

    try:
        # 1. Fetch the last 6 data points from the database
        with connection.cursor() as cursor:
            # We need all the fields for the model input
            query = """
                SELECT temperature, humidity, wind_speed, rain_rate
                FROM weather_reports
                ORDER BY date_time DESC
                LIMIT 6
            """
            cursor.execute(query)
            data_points = cursor.fetchall()

        if len(data_points) < 6:
            print("Not enough data points (less than 6) to run the time-series model. Skipping prediction.")
            return

        # 2. Extract features and combine them with API data
        temperatures = [row[0] for row in data_points]
        humidities = [row[1] for row in data_points]
        wind_speeds_db = [row[2] for row in data_points]
        rain_rates_db = [row[3] for row in data_points]

        # Use the most recent data point for the API call
        latest_sensor_data = data_points[0]
        latest_temp, latest_humidity, latest_wind, latest_rain_rate = latest_sensor_data
        
        # 3. Fetch barometric pressure from external API
        api_key = os.environ.get('OPENWEATHERMAP_API_KEY')
        latitude = os.environ.get('LATITUDE')
        longitude = os.environ.get('LONGITUDE')
        
        _, barometric_pressure = fetch_weather_data_from_api(api_key, latitude, longitude)
        
        # Use a fallback value if barometric pressure is not available
        barometric_pressure_final = barometric_pressure if barometric_pressure is not None else 1013.25
        
        # Create the full input for the model
        input_features = np.array([
            [temperatures[0], humidities[0], wind_speeds_db[0], barometric_pressure_final, time.localtime().tm_hour],
            [temperatures[1], humidities[1], wind_speeds_db[1], barometric_pressure_final, time.localtime().tm_hour],
            [temperatures[2], humidities[2], wind_speeds_db[2], barometric_pressure_final, time.localtime().tm_hour],
            [temperatures[3], humidities[3], wind_speeds_db[3], barometric_pressure_final, time.localtime().tm_hour],
            [temperatures[4], humidities[4], wind_speeds_db[4], barometric_pressure_final, time.localtime().tm_hour],
            [temperatures[5], humidities[5], wind_speeds_db[5], barometric_pressure_final, time.localtime().tm_hour],
        ])

        # 4. Call the prediction model
        rain_rate, duration, intensity = predict_rain(input_features)

        # 5. Log prediction results to the database
        with connection.cursor() as cursor:
            cursor.execute("""
                INSERT INTO ai_predictions (predicted_rain, duration, intensity, created_at)
                VALUES (%s, %s, %s, NOW())
            """, [rain_rate, duration, intensity])

        print("--- Prediction Results ---")
        print(f"Predicted Rainfall: {rain_rate:.2f} mm")
        print(f"Estimated Duration: {duration:.2f} minutes")
        print(f"Rainfall Intensity: {intensity}")

    except Exception as e:
        print(f"Prediction task failed: {str(e)}")
