#!/bin/bash
# Pre-deployment security and quality checks
# Run this script before deploying to production

set -e  # Exit on any error

echo "🔍 Running pre-deployment checks..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0

# 1. Security audit with pip-audit
echo -e "\n${YELLOW}[1/6] Running pip-audit...${NC}"
if command -v pip-audit &> /dev/null; then
    if pip-audit --format=json --output=audit-report.json 2>/dev/null; then
        echo -e "${GREEN}✓ pip-audit passed${NC}"
    else
        echo -e "${RED}✗ pip-audit found vulnerabilities. Check audit-report.json${NC}"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo -e "${YELLOW}⚠ pip-audit not installed. Install with: pip install pip-audit${NC}"
fi

# 2. Safety check
echo -e "\n${YELLOW}[2/6] Running safety check...${NC}"
if command -v safety &> /dev/null; then
    if safety check --json --output=safety-report.json 2>/dev/null; then
        echo -e "${GREEN}✓ safety check passed${NC}"
    else
        echo -e "${RED}✗ safety found vulnerabilities. Check safety-report.json${NC}"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo -e "${YELLOW}⚠ safety not installed. Install with: pip install safety${NC}"
fi

# 3. Django security check
echo -e "\n${YELLOW}[3/6] Checking Django security...${NC}"
python manage.py check --deploy 2>&1 | tee django-security-check.log
if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo -e "${GREEN}✓ Django security check passed${NC}"
else
    echo -e "${RED}✗ Django security check failed${NC}"
    ERRORS=$((ERRORS + 1))
fi

# 4. Code formatting check (black)
echo -e "\n${YELLOW}[4/6] Checking code formatting (black)...${NC}"
if command -v black &> /dev/null; then
    if black --check weatherapp/ weatheralert/ 2>/dev/null; then
        echo -e "${GREEN}✓ Code formatting check passed${NC}"
    else
        echo -e "${RED}✗ Code formatting issues found. Run: black weatherapp/ weatheralert/${NC}"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo -e "${YELLOW}⚠ black not installed. Install with: pip install black${NC}"
fi

# 5. Linting (flake8)
echo -e "\n${YELLOW}[5/6] Running flake8 linting...${NC}"
if command -v flake8 &> /dev/null; then
    if flake8 weatherapp/ weatheralert/ --max-line-length=100 --exclude=migrations; then
        echo -e "${GREEN}✓ Linting passed${NC}"
    else
        echo -e "${RED}✗ Linting issues found${NC}"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo -e "${YELLOW}⚠ flake8 not installed. Install with: pip install flake8${NC}"
fi

# 6. Run tests with coverage
echo -e "\n${YELLOW}[6/6] Running tests with coverage...${NC}"
if command -v coverage &> /dev/null; then
    coverage run --source='weatherapp' manage.py test weatherapp
    COVERAGE=$(coverage report --format=total)
    echo -e "\n${GREEN}Test coverage: ${COVERAGE}%${NC}"
    
    # Check if coverage is above 70%
    if (( $(echo "$COVERAGE >= 70" | bc -l) )); then
        echo -e "${GREEN}✓ Coverage meets requirement (>=70%)${NC}"
        coverage html
        echo -e "${GREEN}Coverage report generated in htmlcov/index.html${NC}"
    else
        echo -e "${RED}✗ Coverage below 70% (current: ${COVERAGE}%)${NC}"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo -e "${YELLOW}⚠ coverage not installed. Running tests without coverage...${NC}"
    python manage.py test weatherapp
fi

# Summary
echo -e "\n${YELLOW}========================================${NC}"
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ All pre-deployment checks passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ ${ERRORS} check(s) failed. Please fix issues before deploying.${NC}"
    exit 1
fi

