import network
import urequests
import time
import dht
from machine import Pin

# WiFi credentials
SSID = "SIASICO"
PASSWORD = "Waykokabalo0831"

# API endpoint
URL = "https://bccweather-629d88a334c9.herokuapp.com/api/data/"

# Connect to WiFi
def connect_wifi():
    wlan = network.WLAN(network.STA_IF)
    wlan.active(True)
    if not wlan.isconnected():
        print("Connecting to WiFi...")
        wlan.connect(SSID, PASSWORD)
        for _ in range(15):
            if wlan.isconnected():
                break
            time.sleep(1)
            print("Waiting for connection...")
    if wlan.isconnected():
        print("Connected, IP:", wlan.ifconfig()[0])
    else:
        raise RuntimeError("WiFi connection failed")
    return wlan

# Main loop
try:
    connect_wifi()
    sensor = dht.DHT11(Pin(4))  # GPIO4 == D4

    while True:
        try:
            sensor.measure()
            temp = sensor.temperature()
            hum = sensor.humidity()

            payload = {
                "temperature": temp,
                "humidity": hum,
                "sensor_id": 1
            }

            print("Sending data:", payload)

            response = urequests.post(URL, json=payload)
            print("Response:", response.status_code, response.text)
            response.close()

        except Exception as e:
            print("Error:", e)

        time.sleep(600)  # wait 10 minutes

except Exception as e:
    print("Fatal error:", e)
