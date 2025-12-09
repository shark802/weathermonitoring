# Pre-Deployment Checklist

This checklist ensures all security, quality, and testing requirements are met before deployment.

## Automated Checks

Run the pre-deployment script:

```bash
./scripts/pre_deployment_check.sh
```

This automatically checks:
- ✅ Security vulnerabilities (pip-audit, safety)
- ✅ Django security settings
- ✅ Code formatting (black)
- ✅ Code quality (flake8)
- ✅ Test coverage (≥70%)

## Manual Checks

### 1. Security Review

- [ ] Review `pip-audit` report for vulnerabilities
- [ ] Review `safety` report for known security issues
- [ ] Check Django security advisories: https://www.djangoproject.com/weblog/
- [ ] Verify `DEBUG=False` in production settings
- [ ] Ensure `SECRET_KEY` is set and secure
- [ ] Review `ALLOWED_HOSTS` configuration
- [ ] Verify SSL/TLS is enabled
- [ ] Check CSRF and session cookie settings

### 2. Code Quality

- [ ] Code formatted with `black`
- [ ] Imports sorted with `isort`
- [ ] No flake8 errors
- [ ] No critical pylint warnings
- [ ] All print statements removed (use logging)

### 3. Testing

- [ ] All unit tests pass
- [ ] All integration tests pass
- [ ] All E2E tests pass
- [ ] Test coverage ≥70%
- [ ] Critical user flows tested:
  - [ ] User registration
  - [ ] User login/logout
  - [ ] Password reset
  - [ ] Admin operations
  - [ ] Sensor data collection
  - [ ] Alert generation

### 4. Database

- [ ] All migrations applied
- [ ] Database backups configured
- [ ] Connection pooling configured (if applicable)
- [ ] Indexes on frequently queried columns

### 5. Performance

- [ ] Redis caching configured
- [ ] Static files collected (`python manage.py collectstatic`)
- [ ] Gunicorn workers configured appropriately
- [ ] Database query optimization reviewed

### 6. Monitoring

- [ ] Error logging configured
- [ ] Performance monitoring enabled
- [ ] Health check endpoints available
- [ ] Alerting configured for critical errors

### 7. Environment Variables

- [ ] All required environment variables set
- [ ] No secrets in code (use environment variables)
- [ ] `.env` file not committed to repository
- [ ] Production secrets different from development

### 8. Documentation

- [ ] README updated
- [ ] API documentation current
- [ ] Deployment instructions documented
- [ ] Environment setup documented

## Quick Commands

```bash
# Run all checks
./scripts/pre_deployment_check.sh

# Run tests with coverage
./scripts/run_tests.sh

# Security audit
pip-audit && safety check

# Code quality
black --check . && flake8 . && isort --check-only .

# Django checks
python manage.py check --deploy
python manage.py collectstatic --noinput
```

## Emergency Rollback

If deployment fails:

1. Restore previous version from backup
2. Restore database backup if needed
3. Review error logs
4. Fix issues before retrying

## Post-Deployment

- [ ] Verify application is accessible
- [ ] Test critical user flows
- [ ] Monitor error logs
- [ ] Check performance metrics
- [ ] Verify caching is working
- [ ] Test rate limiting

