import numpy as np
import joblib
import tensorflow as tf
import os
import requests
import json
import time
from django.db import connection

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
    This function is no longer a mock. It performs an actual API call.
    """
    print("Fetching missing data from weather API...")
    url = f"https://api.openweathermap.org/data/2.5/weather?lat={latitude}&lon={longitude}&appid={api_key}&units=metric"
    try:
        response = requests.get(url, timeout=10)
        response.raise_for_status()  # Raise an HTTPError for bad responses (4xx or 5xx)
        data = response.json()
        
        # Check if the required data exists in the response
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
try:
    model = tf.keras.models.load_model(MODEL_FILE, compile=False)
    model.compile(optimizer="adam", loss="mean_squared_error")
    print("✅ Model loaded successfully.")
    scaler_X = joblib.load(SCALER_X_FILE)
    scaler_y = joblib.load(SCALER_Y_FILE)
    print("✅ Scalers loaded successfully.")
except FileNotFoundError as e:
    print(f"Error: One of the required files was not found: {e.filename}")
    print("Please ensure 'rain_model.h5', 'scaler_X.pkl', and 'scaler_y.pkl' are in the same directory.")
    exit()
except Exception as e:
    print(f"An unexpected error occurred during file loading: {e}")
    exit()

# =======================================================
# 3. Helper and Prediction Functions
# =======================================================
def get_rain_intensity(amount):
    """Categorizes rainfall amount into a label."""
    if amount <= 0:
        return "None"
    elif 0 < amount < 2.5:
        return "Light"
    elif 2.5 <= amount < 7.6:
        return "Moderate"
    elif 7.6 <= amount < 15:
        return "Heavy"
    elif 15 <= amount < 30:
        return "Intense"
    else:
        return "Torrential"

def predict_rain(temperature, humidity, wind_speed, barometric_pressure):
    """Predicts rainfall rate and duration using the loaded model."""
    PAST_STEPS = 6
    # Note: The model's input features must be in the same order as when it was trained.
    input_features = np.array([[temperature, humidity, barometric_pressure, wind_speed, 0]])
    input_scaled = scaler_X.transform(input_features)
    X_seq = np.repeat(input_scaled, PAST_STEPS, axis=0).reshape(1, PAST_STEPS, -1)
    
    y_pred_scaled = model.predict(X_seq, verbose=0)
    y_pred = scaler_y.inverse_transform(y_pred_scaled)
    
    rain_rate = float(y_pred[0][0])
    duration = float(y_pred[0][1])
    
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
    
    # --- Step 1: Fetch data from your database ---
    latest_temp, latest_humidity = get_latest_sensor_data()
    if latest_temp is None or latest_humidity is None:
        print("Could not fetch temperature or humidity from the database. Exiting.")
        return
        
    # --- Step 2: Fetch missing data from a weather API ---
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

    print("\nData collected from all sources:")
    print(f"From your device: Temperature={latest_temp}°C, Humidity={latest_humidity}%")
    print(f"From external API: Wind Speed={wind_speed} m/s, Barometric Pressure={barometric_pressure} hPa")

    # --- Step 3: Combine all data and make the prediction ---
    predicted_rain_rate, predicted_duration, intensity_label = predict_rain(
        temperature=latest_temp,
        humidity=latest_humidity,
        wind_speed=wind_speed,
        barometric_pressure=barometric_pressure
    )

    print("\n--- Prediction Results ---")
    print(f"Predicted Rainfall: {predicted_rain_rate:.2f} mm")
    print(f"Estimated Duration: {predicted_duration:.2f} minutes")
    print(f"Rainfall Intensity: {intensity_label}")

if __name__ == "__main__":
    main()
