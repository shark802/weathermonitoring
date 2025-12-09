# Testing Guide

This guide explains how to run tests, check code quality, and ensure security before deployment.

## Setup

### Install Development Dependencies

```bash
pip install -r requirements-dev.txt
```

### Install Pre-commit Hooks (Optional)

```bash
pip install pre-commit
pre-commit install
```

## Running Tests

### Run All Tests

```bash
python manage.py test weatherapp
```

### Run Tests with Coverage

```bash
./scripts/run_tests.sh
```

Or manually:

```bash
coverage run --source='weatherapp' manage.py test weatherapp
coverage report
coverage html  # Generates htmlcov/index.html
```

### Run Specific Test Files

```bash
# Authentication tests
python manage.py test weatherapp.tests.test_authentication

# Registration tests
python manage.py test weatherapp.tests.test_registration

# Database operation tests
python manage.py test weatherapp.tests.test_database_operations

# API endpoint tests
python manage.py test weatherapp.tests.test_api_endpoints

# E2E flow tests
python manage.py test weatherapp.tests.test_e2e_flows
```

## Code Quality Checks

### Format Code with Black

```bash
black weatherapp/ weatheralert/
```

### Check Code Formatting

```bash
black --check weatherapp/ weatheralert/
```

### Sort Imports with isort

```bash
isort weatherapp/ weatheralert/
```

### Lint with Flake8

```bash
flake8 weatherapp/ weatheralert/ --max-line-length=100 --exclude=migrations
```

### Lint with Pylint

```bash
pylint weatherapp/ weatheralert/
```

## Security Checks

### Run pip-audit

```bash
pip-audit
```

Generate JSON report:

```bash
pip-audit --format=json --output=audit-report.json
```

### Run Safety Check

```bash
safety check
```

Generate JSON report:

```bash
safety check --json --output=safety-report.json
```

### Check Django Security

```bash
python manage.py check --deploy
```

## Pre-Deployment Checklist

Run the complete pre-deployment check script:

```bash
./scripts/pre_deployment_check.sh
```

This script runs:
1. ✅ pip-audit (vulnerability scanning)
2. ✅ safety check (dependency security)
3. ✅ Django security check
4. ✅ Code formatting check (black)
5. ✅ Linting (flake8)
6. ✅ Tests with coverage (must be >=70%)

## Test Coverage

### Current Coverage Target

**Target: ≥70% code coverage**

### View Coverage Report

After running tests with coverage:

```bash
coverage html
open htmlcov/index.html  # On macOS
# Or open htmlcov/index.html in your browser
```

### Coverage Exclusions

The following are excluded from coverage:
- Migration files
- Test files themselves
- Settings files
- WSGI/ASGI files

## Test Structure

```
weatherapp/tests/
├── __init__.py
├── test_authentication.py      # Unit tests for login/logout
├── test_registration.py        # Unit tests for user registration
├── test_database_operations.py # Integration tests for DB operations
├── test_api_endpoints.py       # Integration tests for API endpoints
└── test_e2e_flows.py          # End-to-end user flow tests
```

## Continuous Integration

### GitHub Actions Example

```yaml
name: Tests and Quality Checks

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      - run: pip install -r requirements.txt
      - run: pip install -r requirements-dev.txt
      - run: ./scripts/pre_deployment_check.sh
```

## Django Security Advisories

### Check for Django Security Updates

1. Visit: https://www.djangoproject.com/weblog/
2. Subscribe to Django security announcements
3. Regularly update Django and dependencies

### Current Django Version

Check `requirements.txt` for the installed Django version.

### Update Dependencies

```bash
pip list --outdated
pip install --upgrade django
pip-audit  # Re-check after updates
```

## Troubleshooting

### Tests Failing

1. Ensure test database is properly configured
2. Check that all migrations are applied: `python manage.py migrate`
3. Verify test data setup/teardown in `setUp()` and `tearDown()`

### Coverage Below 70%

1. Identify untested code: `coverage report --show-missing`
2. Add tests for missing coverage
3. Focus on critical paths first (authentication, registration, API endpoints)

### Security Checks Failing

1. Review vulnerability reports
2. Update vulnerable packages
3. Check if vulnerabilities are false positives
4. Document any accepted risks

## Best Practices

1. **Run tests before committing**: Use pre-commit hooks
2. **Maintain coverage**: Aim for >70% and increase over time
3. **Fix security issues immediately**: Don't deploy with known vulnerabilities
4. **Review coverage reports**: Focus on critical business logic
5. **Update dependencies regularly**: Keep packages current
6. **Document test cases**: Explain complex test scenarios

