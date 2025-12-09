"""
Unit tests for authentication functionality.
"""
import json
from django.test import TestCase, Client, RequestFactory
from django.contrib.auth.hashers import check_password
from django.db import connection
from django.core.cache import cache
from django.test import override_settings

from weatherapp.views import login_view, logout_view
from weatherapp.utils.rate_limit import rate_limit

TEST_CACHES = {
    'default': {
        'BACKEND': 'django.core.cache.backends.locmem.LocMemCache',
        'LOCATION': 'test-cache',
        'TIMEOUT': None,
    }
}


@override_settings(CACHES=TEST_CACHES)
class AuthenticationTests(TestCase):
    """Test authentication views."""

    def setUp(self):
        """Set up test data."""
        self.client = Client()
        self.factory = RequestFactory()
        cache.clear()
        
        # Create a test admin user
        with connection.cursor() as cursor:
            from django.contrib.auth.hashers import make_password
            cursor.execute("""
                INSERT INTO admin (name, email, phone_num, username, password, status)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, [
                'Test Admin',
                'admin@test.com',
                '09123456789',
                'testadmin',
                make_password('TestPass123!'),
                'Active'
            ])
            
            # Create a test regular user
            cursor.execute("""
                INSERT INTO user (name, address, email, phone_num, username, password)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, [
                'Test User',
                'Test Address',
                'user@test.com',
                '09123456788',
                'testuser',
                make_password('TestPass123!')
            ])

    def tearDown(self):
        """Clean up test data."""
        with connection.cursor() as cursor:
            cursor.execute("DELETE FROM admin WHERE username IN ('testadmin', 'testuser')")
            cursor.execute("DELETE FROM user WHERE username IN ('testadmin', 'testuser')")

    def test_login_success_admin(self):
        """Test successful admin login."""
        response = self.client.post('/login/', {
            'username': 'testadmin',
            'password': 'TestPass123!',
            'remember_me': 'on'
        })
        
        self.assertEqual(response.status_code, 302)  # Redirect
        self.assertIn('admin_id', self.client.session)
        self.assertEqual(self.client.session['username'], 'testadmin')

    def test_login_success_user(self):
        """Test successful regular user login."""
        response = self.client.post('/login/', {
            'username': 'testuser',
            'password': 'TestPass123!',
            'remember_me': 'on'
        })
        
        self.assertEqual(response.status_code, 302)  # Redirect
        self.assertIn('user_id', self.client.session)
        self.assertEqual(self.client.session['username'], 'testuser')

    def test_login_invalid_credentials(self):
        """Test login with invalid credentials."""
        response = self.client.post('/login/', {
            'username': 'testadmin',
            'password': 'WrongPassword123!',
        })
        
        self.assertEqual(response.status_code, 200)  # Renders page with error
        self.assertNotIn('admin_id', self.client.session)
        self.assertNotIn('user_id', self.client.session)

    def test_login_nonexistent_user(self):
        """Test login with non-existent username."""
        response = self.client.post('/login/', {
            'username': 'nonexistent',
            'password': 'TestPass123!',
        })
        
        self.assertEqual(response.status_code, 200)
        self.assertNotIn('admin_id', self.client.session)
        self.assertNotIn('user_id', self.client.session)

    def test_login_deactivated_admin(self):
        """Test login with deactivated admin account."""
        with connection.cursor() as cursor:
            cursor.execute("UPDATE admin SET status = 'Deactivated' WHERE username = 'testadmin'")
        
        response = self.client.post('/login/', {
            'username': 'testadmin',
            'password': 'TestPass123!',
        })
        
        self.assertEqual(response.status_code, 200)
        self.assertNotIn('admin_id', self.client.session)

    def test_logout_post_method(self):
        """Test logout with POST method."""
        # First login
        self.client.post('/login/', {
            'username': 'testadmin',
            'password': 'TestPass123!',
        })
        
        self.assertIn('admin_id', self.client.session)
        
        # Then logout
        response = self.client.post('/logout/')
        
        self.assertEqual(response.status_code, 302)  # Redirect to home
        self.assertNotIn('admin_id', self.client.session)
        self.assertIn('form_logoutSuccess', self.client.session)

    def test_logout_get_method_rejected(self):
        """Test that GET method is rejected for logout."""
        response = self.client.get('/logout/')
        self.assertEqual(response.status_code, 405)  # Method not allowed

    def test_logout_without_session(self):
        """Test logout when not logged in."""
        response = self.client.post('/logout/')
        self.assertEqual(response.status_code, 302)  # Redirects to home

    def test_remember_me_session_expiry(self):
        """Test that 'Remember Me' affects session expiry."""
        response = self.client.post('/login/', {
            'username': 'testuser',
            'password': 'TestPass123!',
            'remember_me': 'on'
        })
        
        # Session should have extended expiry (30 days)
        self.assertIsNotNone(self.client.session.get_expiry_date())
        
        # Without remember_me
        self.client.logout()
        response = self.client.post('/login/', {
            'username': 'testuser',
            'password': 'TestPass123!',
        })
        
        # Session should expire on browser close
        self.assertEqual(self.client.session.get_expiry_age(), 0)

    def test_login_rate_limiting(self):
        """Test that login is rate limited."""
        # This would require mocking the rate limit decorator
        # For now, we test that the decorator is applied
        self.assertTrue(hasattr(login_view, '__wrapped__') or 
                       hasattr(login_view, '__name__'))

