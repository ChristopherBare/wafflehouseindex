#!/bin/bash

set -e

echo "=== Testing Waffle House Index API Deployment ==="

# Get the CloudFront URL from Terraform
cd terraform
CLOUDFRONT_URL=$(terraform output -raw cloudfront_url 2>/dev/null || echo "")
API_GATEWAY_URL=$(terraform output -raw api_gateway_url 2>/dev/null || echo "")
cd ..

if [ -z "$CLOUDFRONT_URL" ]; then
    echo "❌ Error: No CloudFront URL found. Have you deployed the infrastructure?"
    echo "Run ./deploy.sh first"
    exit 1
fi

echo "🌐 CloudFront URL: $CLOUDFRONT_URL"
echo "🔗 API Gateway URL: $API_GATEWAY_URL"
echo ""

# Test health endpoint
echo "1️⃣ Testing health endpoint..."
HEALTH_RESPONSE=$(curl -s "$CLOUDFRONT_URL/api/health")
if echo "$HEALTH_RESPONSE" | grep -q "healthy"; then
    echo "✅ Health check passed"
    echo "   Response: $HEALTH_RESPONSE"
else
    echo "❌ Health check failed"
    echo "   Response: $HEALTH_RESPONSE"
    exit 1
fi
echo ""

# Test coordinates endpoint (Atlanta)
echo "2️⃣ Testing coordinates endpoint (Atlanta, GA)..."
COORDS_RESPONSE=$(curl -s "$CLOUDFRONT_URL/api/index/coordinates/?lat=33.7490&lon=-84.3880&radius=50")
TOTAL=$(echo "$COORDS_RESPONSE" | grep -o '"total":[0-9]*' | grep -o '[0-9]*')
OPEN=$(echo "$COORDS_RESPONSE" | grep -o '"open_count":[0-9]*' | grep -o '[0-9]*')

if [ -n "$TOTAL" ] && [ "$TOTAL" -gt 0 ]; then
    echo "✅ Coordinates endpoint working"
    echo "   Found $TOTAL stores ($OPEN open)"
else
    echo "❌ Coordinates endpoint failed"
    echo "   Response: $COORDS_RESPONSE"
    exit 1
fi
echo ""

# Test ZIP code endpoint
echo "3️⃣ Testing ZIP code endpoint (30303 - Atlanta)..."
ZIP_RESPONSE=$(curl -s "$CLOUDFRONT_URL/api/index/zip/?zip=30303&radius=50")
ZIP_TOTAL=$(echo "$ZIP_RESPONSE" | grep -o '"total":[0-9]*' | grep -o '[0-9]*')

if [ -n "$ZIP_TOTAL" ] && [ "$ZIP_TOTAL" -gt 0 ]; then
    echo "✅ ZIP code endpoint working"
    echo "   Found $ZIP_TOTAL stores"
else
    echo "❌ ZIP code endpoint failed"
    echo "   Response: $ZIP_RESPONSE"
    exit 1
fi
echo ""

# Test caching
echo "4️⃣ Testing CloudFront caching..."
START_TIME=$(date +%s%N)
curl -s "$CLOUDFRONT_URL/api/index/coordinates/?lat=33.7490&lon=-84.3880&radius=50" > /dev/null
END_TIME=$(date +%s%N)
FIRST_TIME=$((($END_TIME - $START_TIME) / 1000000))

START_TIME=$(date +%s%N)
curl -s "$CLOUDFRONT_URL/api/index/coordinates/?lat=33.7490&lon=-84.3880&radius=50" > /dev/null
END_TIME=$(date +%s%N)
SECOND_TIME=$((($END_TIME - $START_TIME) / 1000000))

echo "   First request: ${FIRST_TIME}ms"
echo "   Second request: ${SECOND_TIME}ms (should be faster due to caching)"

if [ "$SECOND_TIME" -lt "$FIRST_TIME" ]; then
    echo "✅ Caching appears to be working"
else
    echo "⚠️  Second request not faster (might already be cached)"
fi
echo ""

# Test CORS headers
echo "5️⃣ Testing CORS headers..."
CORS_HEADERS=$(curl -s -I "$CLOUDFRONT_URL/api/health" | grep -i "access-control-allow-origin" || echo "")
if [ -n "$CORS_HEADERS" ]; then
    echo "✅ CORS headers present"
    echo "   $CORS_HEADERS"
else
    echo "⚠️  CORS headers not found (may be okay depending on CloudFront config)"
fi
echo ""

echo "=== All tests completed ==="
echo ""
echo "📱 To use in Flutter app:"
echo "1. Edit whi_flutter/lib/config.dart"
echo "2. Set useProduction = true"
echo "3. Set cloudfrontUrl = \"$CLOUDFRONT_URL\""
echo ""
echo "🔍 Example API calls:"
echo "curl \"$CLOUDFRONT_URL/api/index/coordinates/?lat=33.7490&lon=-84.3880&radius=50\""
echo "curl \"$CLOUDFRONT_URL/api/index/zip/?zip=30303&radius=50\""