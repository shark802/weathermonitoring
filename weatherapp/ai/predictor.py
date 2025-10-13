import numpy as np
import joblib
import os
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '2'
os.environ['TF_ENABLE_ONEDNN_OPTS'] = '0' 
import tensorflow as tf
import time
import sys
import django
from django.conf import settings
from django.db import connection
from dotenv import load_dotenv

# Load environment variables (needed for Django settings/DB config)
load_dotenv()

# Define file paths for the model and scalers.
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_FILE = os.path.join(BASE_DIR, "rain_model.h5")
SCALER_X_FILE = os.path.join(BASE_DIR, "scaler_X.pkl")
SCALER_Y_FILE = os.path.join(BASE_DIR, "scaler_y.pkl")

# Define the number of time steps (sequence length) the model requires.
SEQUENCE_LENGTH = 6

# =======================================================
# 1. Database Function (All Data from DB)
# =======================================================
def get_sequence_data_from_db():
    """
    Fetches the last SEQUENCE_LENGTH time steps of all required features
    from the database: temperature, humidity, wind_speed, barometric_pressure,
    and the hour of the day (derived from date_time).

    Returns:
        list[list]: A sequence of historical weather data (oldest to newest),
                    or None if insufficient data is found.
    """
    print(f"Fetching last {SEQUENCE_LENGTH} time steps of data from database...")
    try:
        with connection.cursor() as cursor:
            # NOTE: We assume 'weather_reports' now contains wind_speed and barometric_pressure.
            # We fetch date_time to calculate the 'hour_of_day' feature (0-23).
            query = """
            SELECT temperature, humidity, wind_speed, barometric_pressure, date_time
            FROM weather_reports
            ORDER BY date_time DESC
            LIMIT %s
            """
            cursor.execute(query, [SEQUENCE_LENGTH])
            data = cursor.fetchall()
            
            if not data or len(data) < SEQUENCE_LENGTH:
                print(f"Error: Found only {len(data)} records. {SEQUENCE_LENGTH} required for prediction.")
                return None
            
            # The data is fetched in reverse chronological order (newest first).
            # The sequence must be oldest to newest for the model.
            data.reverse()
            
            sequence = []
            for temp, humid, wind, pressure, dt in data:
                # dt is a datetime object from the database, extract the hour (0-23).
                hour_of_day = float(dt.hour)
                # The 5 features must be in the same order as the model training data.
                sequence.append([
                    float(temp),
                    float(humid),
                    float(wind),
                    float(pressure),
                    hour_of_day
                ])

            return sequence

    except Exception as e:
        print(f"Error reading database for sequence data: {e}")
        print("Please check your database configuration and table schema.")
        return None

# =======================================================
# 2. Model and Scalers Loading
# =======================================================
model = None
scaler_X = None
scaler_y = None

# --- FIX START: Define a dummy InputLayer to handle the 'batch_shape' deprecation ---
class FixedInputLayer(tf.keras.layers.InputLayer):
    """
    A temporary fix class to handle the 'batch_shape' argument, 
    which was present in older Keras models but is unrecognized/deprecated
    in newer Keras/TensorFlow versions.
    """
    def __init__(self, **kwargs):
        # Remove the problematic 'batch_shape' argument if present
        if 'batch_shape' in kwargs:
            kwargs.pop('batch_shape')
        super(FixedInputLayer, self).__init__(**kwargs)
# --- FIX END ---

try:
    # Use the custom_object_scope to substitute the InputLayer during loading
    with tf.keras.utils.custom_object_scope({'InputLayer': FixedInputLayer}):
        model = tf.keras.models.load_model(MODEL_FILE, compile=False)

    model.compile(optimizer="adam", loss="mean_squared_error")
    print("✅ Model loaded successfully.")
    
    scaler_X = joblib.load(SCALER_X_FILE)
    scaler_y = joblib.load(SCALER_Y_FILE)
    print("✅ Scalers loaded successfully.")

except FileNotFoundError as e:
    # ... (rest of the FileNotFoundError block)
    print(f"Warning: One of the required files was not found: {e.filename}")
    print("Please ensure 'rain_model.h5', 'scaler_X.pkl', and 'scaler_y.pkl' are in the same directory.")
    print("ML prediction will be disabled.")
except Exception as e:
    # ... (rest of the generic Exception block)
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
    This function expects a NumPy array of shape (6, 5).
    
    Args:
        input_features (np.ndarray): The (6, 5) sequence of features.

    Returns:
        tuple: (rain_rate, duration, intensity_label)
    """
    
    # Extract the latest data point for fallback prediction
    latest_data = input_features[-1]
    latest_temp, latest_humidity, _, _, _ = latest_data

    if model is None or scaler_X is None or scaler_y is None:
        print("Warning: ML model not loaded. Using fallback prediction.")
        
        # Fallback logic using the latest temperature and humidity
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
        # Reshaping to (6, 5) ensures the scaler works correctly on all 6 steps
        input_scaled = scaler_X.transform(input_features)
    except ValueError as e:
        print(f"Error during scaling: {e}")
        print("This may be due to a mismatch in the number of features (should be 5).")
        return None, None, "Error"

    # Reshape the data for the model (1 sample, 6 time steps, 5 features)
    X_seq = input_scaled.reshape(1, SEQUENCE_LENGTH, -1)
    
    y_pred_scaled = model.predict(X_seq, verbose=0)
    y_pred = scaler_y.inverse_transform(y_pred_scaled)
    
    rain_rate = max(0, float(y_pred[0][0]))
    duration = max(0, float(y_pred[0][1]))
    
    intensity = get_rain_intensity(rain_rate)
    return rain_rate, duration, intensity

def assess_flood_risk(rain_rate, duration, intensity_label):
    """
    Assesses the predicted rain against a simplified set of flood thresholds
    for two example areas (Low-Lying Area and Industrial Area).

    In a real application, these thresholds would come from a configuration
    or a dedicated flood-modeling system.

    Returns:
        list[dict]: A list of active flood warnings (can be empty).
    """
    warnings = []
    
    # --- Example 1: Low-Lying Residential Area Thresholds ---
    # Low-lying areas flood easily, so the threshold is lower.
    # High risk for Moderate rain (rate >= 2.5 mm) or prolonged Light rain (rate > 0.5 and duration > 60 min).
    if rain_rate >= 2.5 or (rain_rate > 0.5 and duration > 60):
        warning = {
            "area": "Low-Lying Residential Area",
            "risk_level": "High",
            "message": f"High risk of flooding due to predicted {intensity_label} rain over {duration:.0f} minutes."
        }
        warnings.append(warning)
    elif rain_rate > 1.0: # Moderate risk for persistent light rain
        warning = {
            "area": "Low-Lying Residential Area",
            "risk_level": "Moderate",
            "message": f"Moderate risk of standing water/minor flooding. Monitor conditions."
        }
        warnings.append(warning)

    # --- Example 2: Industrial Area Thresholds ---
    # Industrial areas often have better drainage, so the threshold is higher.
    # Risk for Heavy rain (rate >= 7.6 mm) or Intense rain.
    if rain_rate >= 7.6 or intensity_label in ["Heavy", "Intense", "Torrential"]:
        warning = {
            "area": "Industrial Area",
            "risk_level": "High",
            "message": f"High risk of localized flooding affecting operations due to predicted {intensity_label} rain."
        }
        warnings.append(warning)
        
    return warnings

# =======================================================
# 4. Main Execution Block
# =======================================================
def main():
    """Main function to orchestrate data fetching and prediction."""
    print("\n--- Live Rainfall Prediction Demo (Database Only) ---")
    
    try:
        # Django setup (copied from original)
        project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
        sys.path.append(project_root)
        os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'weather_app.settings')
        django.setup()
        
        # --- Step 1: Fetch 6 steps of data from your database ---
        sequence_data_list = get_sequence_data_from_db()
        
        if sequence_data_list is None:
            print("Prediction failed due to insufficient or missing data. Exiting.")
            return

        # Convert list of lists (6, 5) to NumPy array for ML processing
        input_features_array = np.array(sequence_data_list, dtype=np.float32)

        # Extract the latest data point for display
        # Order: [temp, humid, wind, pressure, hour_of_day]
        latest_temp, latest_humidity, wind_speed, barometric_pressure, current_hour = input_features_array[-1]
        
        print("\nData collected from the database (latest entry):")
        print(f"Temperature: {latest_temp:.2f}°C, Humidity: {latest_humidity:.2f}%")
        print(f"Wind Speed: {wind_speed:.2f} m/s, Barometric Pressure: {barometric_pressure:.2f} hPa")
        print(f"Hour of Day: {int(current_hour)}")
        
        # --- Step 2: Make the prediction ---
        # Pass the full (6, 5) feature array to the prediction function
        predicted_rain_rate, predicted_duration, intensity_label = predict_rain(input_features_array)
        
        if predicted_rain_rate is None:
            print("Prediction failed during ML model execution.")
            return

        print("\n--- Prediction Results ---")
        print(f"Predicted Rainfall: {predicted_rain_rate:.2f} mm")
        print(f"Estimated Duration: {predicted_duration:.2f} minutes")
        print(f"Rainfall Intensity: {intensity_label}")

        # --- Step 3: Insert Rain Prediction results into the database ---
        try:
            with connection.cursor() as cursor:
                # Insert the prediction results
                cursor.execute("""
                    INSERT INTO ai_predictions (predicted_rain, duration, intensity, prediction_date)
                    VALUES (%s, %s, %s, NOW())
                """, [predicted_rain_rate, predicted_duration, intensity_label])
            print("✅ Rain prediction results successfully inserted into the database.")
        except Exception as e:
            print(f"❌ Error inserting rain prediction results into the database: {e}")
            
        # ------------------------------------------------------------------
        # --- Step 4: Assess Flood Risk and Insert Flood Warnings (NEW) ---
        # ------------------------------------------------------------------
        flood_warnings = assess_flood_risk(predicted_rain_rate, predicted_duration, intensity_label)
        
        if flood_warnings:
            print("\n--- FLOOD WARNINGS ISSUED ---")
            try:
                with connection.cursor() as cursor:
                    for warning in flood_warnings:
                        print(f"🚨 {warning['risk_level']} Risk for {warning['area']}: {warning['message']}")
                        
                        # Insert the flood warning results
                        cursor.execute("""
                            INSERT INTO flood_warnings (area, risk_level, message, prediction_date)
                            VALUES (%s, %s, %s, NOW())
                        """, [warning['area'], warning['risk_level'], warning['message']])
                print("✅ Flood warnings successfully inserted into the database.")
            except Exception as e:
                print(f"❌ Error inserting flood warnings into the database: {e}")
        else:
            print("\nNo flood warnings issued for the target areas.")


    except Exception as e:
        print(f"An unexpected error occurred in the main function: {e}")

if __name__ == "__main__":
    main()
