import numpy as np
import joblib
import tensorflow as tf
import os
import requests
import json
import time
import sys
import django
from django.conf import settings
from django.db import connection
from dotenv import load_dotenv

# ❗ NEW: Call load_dotenv() to load variables from the .env file
load_dotenv()

# Define file paths for the model and scalers.
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_FILE = os.path.join(BASE_DIR, "rain_model.h5")
SCALER_X_FILE = os.path.join(BASE_DIR, "scaler_X.pkl")
SCALER_Y_FILE = os.path.join(BASE_DIR, "scaler_y.pkl")

# =======================================================
# 1. Database and API Functions
# =======================================================
def get_latest_sensor_data():
    """
    Fetches the latest temperature and humidity from the database using Django's connection.
    """
    try:
        with connection.cursor() as cursor:
            query = "SELECT temperature, humidity FROM weather_reports ORDER BY date_time DESC LIMIT 1"
            cursor.execute(query)
            data = cursor.fetchone()
            return data if data else (None, None)
    except Exception as e:
        print(f"Error connecting to database: {e}")
        print("Please check your database configuration.")
        return None, None

def fetch_weather_data_from_api(api_key, latitude, longitude):
    """
    Fetches wind speed and barometric pressure from a weather API (e.g., OpenWeatherMap).
    """
    print("Fetching missing data from weather API...")
    url = f"https://api.openweathermap.org/data/2.5/weather?lat={latitude}&lon={longitude}&appid={api_key}&units=metric"
    try:
        response = requests.get(url, timeout=10)
        response.raise_for_status()  # Raise an HTTPError for bad responses (4xx or 5xx)
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
        print("Please check your API key and network connection.")
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
    print("Please ensure 'rain_model.h5', 'scaler_X.pkl', and 'scaler_y.pkl' are in the same directory.")
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

def predict_rain(input_features):
    """
    Predicts rainfall rate and duration using the loaded model.
    This function now expects a NumPy array of shape (6, 5).
    """
    if model is None or scaler_X is None or scaler_y is None:
        print("Warning: ML model not loaded. Using fallback prediction.")
        latest_temp = input_features[0][0]
        latest_humidity = input_features[0][1]
        
        if latest_humidity > 80 and latest_temp < 30:
            rain_rate = 5.0
            duration = 30.0
        elif latest_humidity > 70:
            rain_rate = 2.0
            duration = 15.0
        else:
            rain_rate = 0.5
            duration = 5.0
        
        intensity = get_rain_intensity(rain_rate)
        return rain_rate, duration, intensity
    
    try:
        # Scale the entire 6-step input array
        input_scaled = scaler_X.transform(input_features)
    except ValueError as e:
        print(f"Error during scaling: {e}")
        print("This may be due to a mismatch in the number of features.")
        return None, None, "Error"

    # Reshape the data for the model (1 sample, 6 time steps, 5 features)
    X_seq = input_scaled.reshape(1, 6, -1)
    
    y_pred_scaled = model.predict(X_seq, verbose=0)
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
    
    try:
        # The fix for the `ModuleNotFoundError` from the previous step.
        project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
        sys.path.append(project_root)
        
        os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'weather_app.settings')
        django.setup()
        
        # These variables will now be loaded from your .env file
        api_key = os.environ.get('OPENWEATHERMAP_API_KEY')
        latitude = os.environ.get('LATITUDE')
        longitude = os.environ.get('LONGITUDE')
        
        # --- Step 1: Fetch data from your database ---
        if not all([api_key, latitude, longitude]):
            print("Error: Missing API key or coordinates in environment variables. Exiting.")
            return
            
        try:
            latitude = float(latitude)
            longitude = float(longitude)
        except (ValueError, TypeError):
            print("Error: Latitude or Longitude environment variables are not valid numbers. Exiting.")
            return

        wind_speed, barometric_pressure = fetch_weather_data_from_api(api_key, latitude, longitude)
        if wind_speed is None or barometric_pressure is None:
            print("Failed to fetch wind speed or pressure from API. Exiting.")
            return
            
        latest_temp, latest_humidity = get_latest_sensor_data()
        if latest_temp is None or latest_humidity is None:
            print("Could not fetch temperature or humidity from the database. Exiting.")
            return
        
        # ❗ ADDED `current_hour` to the data collection
        current_hour = time.localtime().tm_hour

        print("\nData collected from all sources:")
        print(f"From your device: Temperature={latest_temp}°C, Humidity={latest_humidity}%")
        print(f"From external API: Wind Speed={wind_speed} m/s, Barometric Pressure={barometric_pressure} hPa")
        print(f"Current Hour: {current_hour}")

        # --- Step 3: Combine all data and make the prediction ---
        predicted_rain_rate, predicted_duration, intensity_label = predict_rain(
            temperature=latest_temp,
            humidity=latest_humidity,
            wind_speed=wind_speed,
            barometric_pressure=barometric_pressure,
            current_hour=current_hour
        )
        
        if predicted_rain_rate is None:
            return

        print("\n--- Prediction Results ---")
        print(f"Predicted Rainfall: {predicted_rain_rate:.2f} mm")
        print(f"Estimated Duration: {predicted_duration:.2f} minutes")
        print(f"Rainfall Intensity: {intensity_label}")

        # --- Step 4: Insert results into the database ---
        try:
            with connection.cursor() as cursor:
                cursor.execute("""
                    INSERT INTO ai_predictions (predicted_rain, duration, intensity)
                    VALUES (%s, %s, %s)
                """, [predicted_rain_rate, predicted_duration, intensity_label])
            print("✅ Prediction results successfully inserted into the database.")
        except Exception as e:
            print(f"❌ Error inserting prediction results into the database: {e}")

    except Exception as e:
        print(f"An unexpected error occurred in the main function: {e}")

if __name__ == "__main__":
    main()
