"""
Test suite for WeatherAlert application.

This module contains unit tests for utility functions and basic functionality.
For comprehensive tests, see:
- test_authentication.py - Authentication tests
- test_registration.py - Registration tests
- test_database_operations.py - Database integration tests
- test_api_endpoints.py - API endpoint tests
- test_e2e_flows.py - End-to-end user flow tests
"""
import json

from django.core.cache import cache
from django.http import JsonResponse
from django.test import RequestFactory, SimpleTestCase, override_settings

from weatherapp.utils.rate_limit import rate_limit
from weatherapp.views import (
    get_rain_intensity,
    get_wind_signal,
    receive_sensor_data,
)


TEST_CACHES = {
    'default': {
        'BACKEND': 'django.core.cache.backends.locmem.LocMemCache',
        'LOCATION': 'test-cache',
        'TIMEOUT': None,
    }
}


@override_settings(CACHES=TEST_CACHES)
class RateLimitDecoratorTests(SimpleTestCase):
    def setUp(self):
        self.factory = RequestFactory()
        cache.clear()

    def _build_view(self, limit=2, window=60, methods=None):
        @rate_limit("rl-test", limit=limit, window=window, methods=methods)
        def sample_view(request):
            return JsonResponse({"ok": True})

        return sample_view

    def test_blocks_requests_after_limit(self):
        view = self._build_view(limit=2, window=60)

        for _ in range(2):
            response = view(self.factory.post("/sample/"))
            self.assertEqual(response.status_code, 200)

        blocked_response = view(self.factory.post("/sample/"))
        self.assertEqual(blocked_response.status_code, 429)
        payload = json.loads(blocked_response.content)
        self.assertIn("retry_after", payload)
        self.assertIn("Retry-After", blocked_response.headers)

    def test_ignored_methods_bypass_limit(self):
        view = self._build_view(limit=1, methods=["POST"])

        for _ in range(3):
            response = view(self.factory.get("/sample/"))
            self.assertEqual(response.status_code, 200)


class RainAndWindHelpersTests(SimpleTestCase):
    def test_get_rain_intensity_boundaries(self):
        self.assertEqual(get_rain_intensity(0), "No Rain")
        self.assertEqual(get_rain_intensity(5), "Moderate")
        self.assertEqual(get_rain_intensity(20), "Intense")

    def test_get_wind_signal_levels(self):
        self.assertEqual(get_wind_signal(0), "No Signal")
        self.assertEqual(get_wind_signal(9), "Signal 1")  # ~32 km/h
        self.assertEqual(get_wind_signal(50), "Signal 5")  # ~180 km/h


@override_settings(CACHES=TEST_CACHES)
class ReceiveSensorDataTests(SimpleTestCase):
    def setUp(self):
        self.factory = RequestFactory()
        cache.clear()

    def test_rejects_non_post_requests(self):
        response = receive_sensor_data(self.factory.get("/api/data/"))
        self.assertEqual(response.status_code, 405)
        payload = json.loads(response.content)
        self.assertIn("error", payload)

    def test_invalid_json_payload_returns_400(self):
        response = receive_sensor_data(
            self.factory.post(
                "/api/data/",
                data="not-json",
                content_type="application/json",
            )
        )
        self.assertEqual(response.status_code, 400)
        payload = json.loads(response.content)
        self.assertEqual(payload["error"], "Invalid payload.")
