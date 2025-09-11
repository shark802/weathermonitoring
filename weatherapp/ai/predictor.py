import numpy as np
import joblib
import tensorflow as tf
import os
import requests
import json
import time
import mysql.connector
from mysql.connector import Error

# Define file paths for the model and scalers.
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_FILE = os.path.join(BASE_DIR, "rain_model.h5")
SCALER_X_FILE = os.path.join(BASE_DIR, "scaler_X.pkl")
SCALER_Y_FILE = os.path.join(BASE_DIR, "scaler_y.pkl")

# =======================================================
# 1. Database and API Functions
# =======================================================
def get_latest_sensor_data(db_config):
    """
    Fetches the latest temperature and humidity from your MySQL database.
    This function now takes a dictionary of database configurations, which should be
    sourced from environment variables for security.
    """
    conn = None
    try:
        conn = mysql.connector.connect(**db_config)
        if conn.is_connected():
            cursor = conn.cursor()
            query = "SELECT temperature, humidity FROM weather_reports ORDER BY date_time DESC LIMIT 1"
            cursor.execute(query)
            data = cursor.fetchone()
            return data if data else (None, None)
    except Error as e:
        print(f"Error connecting to MySQL database: {e}")
        print("Please check your database credentials and connection.")
    finally:
        if conn and conn.is_connected():
            conn.close()
            print("MySQL connection closed.")
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

    # === CONFIGURATION FROM ENVIRONMENT VARIABLES ===
    # For security, database credentials and API keys should not be hardcoded.
    # Set these environment variables before running the script:
    # export MYSQL_USER='your_mysql_username'
    # export MYSQL_PASSWORD='your_mysql_password'
    # export MYSQL_HOST='your_mysql_host'
    # export MYSQL_DATABASE='your_mysql_database'
    # export OPENWEATHERMAP_API_KEY='your_api_key'
    # export LATITUDE='35.7796'
    # export LONGITUDE='-78.6382'
    
    db_config = {
        'user': os.environ.get('u520834156_uWApp2024'),
        'password': os.environ.get('bIxG2Z$In#8'),
        'host': os.environ.get('153.92.15.8'),
        'database': os.environ.get('u520834156_dbweatherApp')
    }
    api_key = os.environ.get('c340398fbf11b1f8ccd73c40f006a0fe')
    latitude = os.environ.get('10.5283')
    longitude = os.environ.get('122.8338')
    
    # --- Step 1: Fetch data from your database ---
    latest_temp, latest_humidity = get_latest_sensor_data(db_config)
    if latest_temp is None or latest_humidity is None:
        print("Could not fetch temperature or humidity from the database. Exiting.")
        return
        
    # --- Step 2: Fetch missing data from a weather API ---
    if not all([api_key, latitude, longitude]):
        print("Error: Missing API key or coordinates in environment variables. Exiting.")
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
