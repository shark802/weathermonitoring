import network
import urequests
import time
import dht
from machine import Pin

ssid = "Genesis"
password = "@bccbsis2024"

def connect_wifi():
    sta = network.WLAN(network.STA_IF)
    if not sta.active():
        sta.active(True)
    
    if not sta.isconnected():
        print("Connecting to WiFi...")
        sta.connect(ssid, password)
        
        max_wait = 10
        while max_wait > 0:
            if sta.isconnected():
                break
            max_wait -= 1
            print('waiting...')
            time.sleep(1)
    
    if not sta.isconnected():
        raise OSError("Failed to connect to WiFi")
    
    print("WiFi connected. IP:", sta.ifconfig()[0])
    return sta

try:
    sta = connect_wifi()
    
    sensor = dht.DHT11(Pin(4))
    url = "https://bccweather-629d88a334c9.herokuapp.com/api/data/"

    while True:
        try:
            sensor.measure()
            temp = sensor.temperature()
            hum = sensor.humidity()

            payload = {
                "temperature": temp,
                "humidity": hum,
                "sensor_id": "1"
            }

            response = urequests.post(url, json=payload)
            print("Server response:", response.text)
            response.close()

        except Exception as e:
            print("Error during sensor reading or HTTP request:", e)
            if not sta.isconnected():
                print("WiFi disconnected, attempting to reconnect...")
                sta = connect_wifi()

        time.sleep(600)

except OSError as e:
    print("Fatal error:", e)