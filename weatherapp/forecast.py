import requests
from datetime import datetime

def get_five_day_forecast():
    api_key = 'c340398fbf11b1f8ccd73c40f006a0fe'
    lat = 10.5283
    lon = 122.8338
    url = 'https://api.openweathermap.org/data/2.5/forecast'
    params = {
        'lat': lat,
        'lon': lon,
        'units': 'metric',
        'appid': api_key
    }

    try:
        response = requests.get(url, params=params)
        response.raise_for_status()
        data = response.json()

        daily_forecast = {}

        for entry in data['list']:
            date_str = datetime.fromtimestamp(entry['dt']).strftime('%Y-%m-%d')
            time_str = datetime.fromtimestamp(entry['dt']).strftime('%H:%M')

            if date_str not in daily_forecast:
                daily_forecast[date_str] = {
                    'temps': [],
                    'description': entry['weather'][0]['description']
                }

            daily_forecast[date_str]['temps'].append(entry['main']['temp'])

        result = []
        for date, info in list(daily_forecast.items())[:5]:
            day_temp = max(info['temps'])
            night_temp = min(info['temps'])
            result.append({
                'date': datetime.strptime(date, '%Y-%m-%d').strftime('%a, %b %d'),
                'temp_day': round(day_temp, 1),
                'temp_night': round(night_temp, 1),
                'description': info['description']
            })

        return result

    except Exception as e:
        return {'error': str(e)}
