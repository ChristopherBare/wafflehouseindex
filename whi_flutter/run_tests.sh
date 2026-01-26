#!/bin/bash
# Script to run Flutter tests with optional coverage

echo "Running Flutter tests..."
echo "========================"

if [ "$1" == "--coverage" ]; then
    echo "Running with coverage..."
    flutter test --coverage
    echo ""
    echo "Coverage report generated in coverage/lcov.info"
    echo "To view HTML report, you can use:"
    echo "  genhtml coverage/lcov.info -o coverage/html"
    echo "  open coverage/html/index.html"
else
    flutter test
fi

echo ""
echo "Test run complete!"