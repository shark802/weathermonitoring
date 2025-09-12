import numpy as np
import joblib
import tensorflow as tf
import os
import requests
import json
import time
from django.db import connection
from apscheduler.schedulers.blocking import BlockingScheduler

# Define file paths for the model and scalers.
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_FILE = os.path.join(BASE_DIR, "rain_model.h5")
SCALER_X_FILE = os.path.join(BASE_DIR, "scaler_X.pkl")
SCALER_Y_FILE = os.path.join(BASE_DIR, "scaler_y.pkl")

# =======================================================
# 1. Database and API Functions
# =======================================================
def get_recent_sensor_data(limit=6):
    """
    Fetches the latest 'limit' number of temperature and humidity readings
    from the database, ordered by date_time.
    """
    try:
        with connection.cursor() as cursor:
            query = f"SELECT temperature, humidity, date_time FROM weather_reports ORDER BY date_time DESC LIMIT {limit}"
            cursor.execute(query)
            data = cursor.fetchall()
            # Ensure chronological order (oldest to newest)
            data.reverse() 
            return data
    except Exception as e:
        print(f"Error connecting to database: {e}")
        return []

def fetch_weather_data_from_api(api_key, latitude, longitude):
    """
    Fetches wind speed and barometric pressure from a weather API (e.g., OpenWeatherMap).
    """
    print("Fetching missing data from weather API...")
    url = f"https://api.openweathermap.org/data/2.5/weather?lat={latitude}&lon={longitude}&appid={api_key}&units=metric"
    try:
        response = requests.get(url, timeout=10)
        response.raise_for_status()
        data = response.json()
        
        wind_speed = data.get('wind', {}).get('speed')
        pressure = data.get('main', {}).get('pressure')
        
        if wind_speed is not None and pressure is not None:
            return wind_speed, pressure
        else:
            print("Required data not found in API response.")
            return None, None
            
    except requests.exceptions.RequestException as e:
        print(f"Error connecting to the weather API: {e}")
        return None, None
    except Exception as e:
        print(f"An unexpected error occurred during the API call: {e}")
        return None, None

# =======================================================
# 2. Model and Scalers Loading
# =======================================================
model = None
scaler_X = None
scaler_y = None

try:
    model = tf.keras.models.load_model(MODEL_FILE, compile=False)
    model.compile(optimizer="adam", loss="mean_squared_error")
    print("✅ Model loaded successfully.")
    scaler_X = joblib.load(SCALER_X_FILE)
    scaler_y = joblib.load(SCALER_Y_FILE)
    print("✅ Scalers loaded successfully.")
except FileNotFoundError as e:
    print(f"Warning: One of the required files was not found: {e.filename}")
    print("ML prediction will be disabled.")
except Exception as e:
    print(f"Warning: An unexpected error occurred during file loading: {e}")
    print("ML prediction will be disabled.")

# =======================================================
# 3. Helper and Prediction Functions
# =======================================================
def get_rain_intensity(amount):
    """Categorizes rainfall amount into a label."""
    if amount <= 0.01:
        return "None"
    elif 0.01 < amount < 2.5:
        return "Light"
    elif 2.5 <= amount < 7.6:
        return "Moderate"
    elif 7.6 <= amount < 15:
        return "Heavy"
    elif 15 <= amount < 30:
        return "Intense"
    else:
        return "Torrential"

def predict_multiple_points(recent_data, wind_speed, barometric_pressure):
    """
    Predicts rainfall for a sequence of data points.
    """
    if model is None or scaler_X is None or scaler_y is None:
        print("Model not loaded. Cannot perform sequential prediction.")
        return None, None, "Error"
    
    PAST_STEPS = 6
    if len(recent_data) < PAST_STEPS:
        print(f"Not enough data points. Need {PAST_STEPS}, but got {len(recent_data)}. Cannot predict.")
        return None, None, "Error"

    input_sequence = []
    for temp, humidity, _ in recent_data:
        input_sequence.append([temp, humidity, wind_speed, barometric_pressure])
    
    input_array = np.array(input_sequence).reshape(1, PAST_STEPS, -1)
    
    try:
        scaled_input = scaler_X.transform(input_array.reshape(-1, input_array.shape[-1]))
        scaled_input = scaled_input.reshape(1, PAST_STEPS, -1)
    except ValueError as e:
        print(f"Error during scaling: {e}")
        return None, None, "Error"

    y_pred_scaled = model.predict(scaled_input, verbose=0)
    y_pred = scaler_y.inverse_transform(y_pred_scaled)
    
    rain_rate = max(0, float(y_pred[0][0]))
    duration = max(0, float(y_pred[0][1]))
    intensity = get_rain_intensity(rain_rate)
    
    return rain_rate, duration, intensity

# =======================================================
# 4. Main Execution Block
# =======================================================
def main():
    """Main function to orchestrate data fetching and prediction."""
    print("\n--- Live Rainfall Prediction Demo with API Integration ---")

    api_key = os.environ.get('OPENWEATHERMAP_API_KEY')
    latitude = os.environ.get('LATITUDE')
    longitude = os.environ.get('LONGITUDE')
    
    if not all([api_key, latitude, longitude]):
        print("Error: Missing API key or coordinates in environment variables. Exiting.")
        return
        
    try:
        latitude = float(latitude)
        longitude = float(longitude)
    except (ValueError, TypeError):
        print("Error: Latitude or Longitude environment variables are not valid numbers. Exiting.")
        return

    # Fetch the required number of data points
    recent_sensor_data = get_recent_sensor_data(limit=6)

    # Fetch missing data from a weather API
    wind_speed, barometric_pressure = fetch_weather_data_from_api(api_key, latitude, longitude)
    if wind_speed is None or barometric_pressure is None:
        print("Failed to fetch wind speed or pressure from API. Exiting.")
        return

    # Perform the prediction on the entire sequence
    predicted_rain_rate, predicted_duration, intensity_label = predict_multiple_points(
        recent_sensor_data,
        wind_speed,
        barometric_pressure
    )

    if predicted_rain_rate is None:
        return

    print("\n--- Prediction Results ---")
    print(f"Predicted Rainfall: {predicted_rain_rate:.2f} mm")
    print(f"Estimated Duration: {predicted_duration:.2f} minutes")
    print(f"Rainfall Intensity: {intensity_label}")

if __name__ == "__main__":
    scheduler = BlockingScheduler()
    # Schedule the main function to run at the top of every hour (e.g., 1:00, 2:00, etc.)
    scheduler.add_job(main, 'cron', hour='*')
    print("Scheduler started. Prediction will run at the start of every hour.")
    try:
        scheduler.start()
    except (KeyboardInterrupt, SystemExit):
        pass