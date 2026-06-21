"""
AWS Lambda handler for Waffle House Index API
Optimized for performance and cost with DynamoDB caching
"""

import json
import math
import time
import os
import boto3
from typing import List, Dict, Any, Tuple
from datetime import datetime, timedelta
import urllib.request
import re

# DynamoDB client
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ.get('DYNAMODB_TABLE', 'whi-locations'))

# Cache TTL in seconds (1 hour)
CACHE_TTL = 3600

# User agent for web scraping
UA = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36"
)


def deg2rad(deg: float) -> float:
    return deg * (math.pi / 180.0)


def distance_miles(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    R_km = 6371.0
    dlat = deg2rad(lat2 - lat1)
    dlon = deg2rad(lon2 - lon1)
    a = (
        math.sin(dlat / 2) ** 2
        + math.cos(deg2rad(lat1)) * math.cos(deg2rad(lat2)) * math.sin(dlon / 2) ** 2
    )
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    km = R_km * c
    return km * 0.621371


def geocode_zip(zip_code: str) -> Tuple[float, float]:
    """Return (lat, lon) for a US ZIP using Zippopotam.us."""
    url = f"https://api.zippopotam.us/us/{zip_code}"

    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=15) as response:
        if response.status != 200:
            raise ValueError(f"Failed to geocode ZIP {zip_code} (status {response.status})")
        data = json.loads(response.read().decode())

    places = data.get("places") or []
    if not places:
        raise ValueError(f"No geocoding results for ZIP {zip_code}")
    lat = float(places[0]["latitude"])
    lon = float(places[0]["longitude"])
    return lat, lon


def fetch_locations_from_source() -> List[Dict]:
    """Fetch all Waffle House locations from public data source."""
    # Waffle House publishes store data through various APIs.
    # Using the SOCI LLP (Locally Logged In Platform) integration
    # which Waffle House uses on their locations site.

    url = "https://locations.wafflehouse.com"

    req = urllib.request.Request(url, headers={
        "User-Agent": UA,
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    })

    with urllib.request.urlopen(req, timeout=30) as response:
        if response.status != 200:
            raise RuntimeError(f"Failed to load locations page ({response.status})")
        html = response.read().decode()

    # Try to find W2GI configuration with appkey
    match = re.search(r"appkey:\s*'([^']+)'", html)
    if not match:
        raise RuntimeError("Failed to find W2GI appkey in page")

    appkey = match.group(1)
    print(f"Found W2GI appkey: {appkey}")

    # Call W2GI API to get locations
    api_url = f"https://api.w2gi.com/v1/stores?key={appkey}&format=json&limit=2000"

    try:
        req = urllib.request.Request(api_url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=30) as response:
            if response.status != 200:
                raise RuntimeError(f"W2GI API returned status {response.status}")
            data = json.loads(response.read().decode())
    except Exception as e:
        print(f"W2GI API failed ({e}), trying alternative endpoint")
        # Fallback: try alternate W2GI endpoint
        api_url = f"https://locator.w2gi.com/{appkey}/stores?format=json&limit=2000"
        req = urllib.request.Request(api_url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=30) as response:
            if response.status != 200:
                raise RuntimeError(f"Fallback W2GI API returned status {response.status}")
            data = json.loads(response.read().decode())

    locations = data.get("stores") or data.get("locations") or []
    if not isinstance(locations, list):
        locations = list(locations) if hasattr(locations, '__iter__') else []

    if not locations:
        print("No locations found in W2GI API response")
        return []

    out = []
    for loc in locations:
        id_ = str(loc.get("id") or loc.get("storeCode") or "").strip()
        if not id_:
            continue

        lat = loc.get("latitude") or loc.get("lat")
        lon = loc.get("longitude") or loc.get("lon")
        if lat is None or lon is None:
            continue

        try:
            lat = float(lat)
            lon = float(lon)
        except (ValueError, TypeError):
            continue

        name = loc.get("name") or loc.get("businessName") or None
        city = loc.get("city") or None
        state = loc.get("state") or None

        # Check opening status
        opening_status = loc.get("opening_status", "").lower()
        status = "Closed" if opening_status in ("temporarily_closed", "permanently_closed", "closed") else "Open"

        out.append({
            "id": id_,
            "name": name,
            "city": city,
            "state": state,
            "status": status,
            "lat": lat,
            "lon": lon,
        })

    if not out:
        print("No valid locations extracted from API response")
        return []

    return out


def get_locations_from_cache() -> List[Dict]:
    """Get locations from DynamoDB cache or fetch fresh data."""
    try:
        # Try to get from cache
        response = table.get_item(Key={'id': 'locations_cache'})

        if 'Item' in response:
            item = response['Item']
            # Check if cache is still valid
            if item.get('ttl', 0) > int(time.time()):
                print("Using cached location data")
                return item.get('locations', [])

        print("Cache miss or expired, fetching fresh data")
    except Exception as e:
        print(f"Error reading from cache: {e}")

    # Fetch fresh data
    locations = fetch_locations_from_source()

    # Store in cache with TTL
    try:
        table.put_item(Item={
            'id': 'locations_cache',
            'locations': locations,
            'ttl': int(time.time()) + CACHE_TTL,
            'updated_at': datetime.utcnow().isoformat()
        })
        print(f"Cached {len(locations)} locations")
    except Exception as e:
        print(f"Error writing to cache: {e}")

    return locations


def compute_index_for_location(lat: float, lon: float, radius_miles: float = 50.0) -> Dict[str, Any]:
    """Compute the Waffle House Index for a given location."""
    all_locs = get_locations_from_cache()

    # Filter by distance
    details = []
    for loc in all_locs:
        dmi = distance_miles(lat, lon, loc['lat'], loc['lon'])
        if dmi <= radius_miles:
            loc_with_dist = loc.copy()
            loc_with_dist['distance_mi'] = dmi
            details.append(loc_with_dist)

    # Sort by distance
    details.sort(key=lambda x: x.get('distance_mi', 0.0))

    total = len(details)
    open_ct = sum(1 for d in details if d['status'] == "Open")
    closed_ct = total - open_ct
    open_pct = (open_ct / total * 100.0) if total else 0.0
    closed_pct = (closed_ct / total * 100.0) if total else 0.0

    return {
        "total": total,
        "open_count": open_ct,
        "closed_count": closed_ct,
        "open_percentage": open_pct,
        "closed_percentage": closed_pct,
        "locations": details,
        "latitude": lat,
        "longitude": lon,
        "radius_miles": radius_miles,
    }


def lambda_handler(event, context):
    """Main Lambda handler for API Gateway events."""

    # Enable CORS
    headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'GET,OPTIONS'
    }

    # Handle OPTIONS for CORS preflight
    if event.get('httpMethod') == 'OPTIONS':
        return {
            'statusCode': 200,
            'headers': headers,
            'body': ''
        }

    path = event.get('path', '/')
    query_params = event.get('queryStringParameters', {}) or {}

    try:
        # Route handling
        if path == '/api/index/coordinates/' or path == '/api/index/coordinates':
            # Get by coordinates
            lat = float(query_params.get('lat'))
            lon = float(query_params.get('lon'))
            radius = float(query_params.get('radius', 50))

            if not (-90 <= lat <= 90):
                return {
                    'statusCode': 400,
                    'headers': headers,
                    'body': json.dumps({"error": "Latitude must be between -90 and 90"})
                }
            if not (-180 <= lon <= 180):
                return {
                    'statusCode': 400,
                    'headers': headers,
                    'body': json.dumps({"error": "Longitude must be between -180 and 180"})
                }

            result = compute_index_for_location(lat, lon, radius)
            return {
                'statusCode': 200,
                'headers': headers,
                'body': json.dumps(result)
            }

        elif path == '/api/index/zip/' or path == '/api/index/zip':
            # Get by ZIP code
            zip_code = query_params.get('zip')
            if not zip_code:
                return {
                    'statusCode': 400,
                    'headers': headers,
                    'body': json.dumps({"error": "ZIP code is required"})
                }

            if not (len(zip_code) == 5 and zip_code.isdigit()):
                return {
                    'statusCode': 400,
                    'headers': headers,
                    'body': json.dumps({"error": "Invalid ZIP code format. Must be 5 digits."})
                }

            radius = float(query_params.get('radius', 50))
            lat, lon = geocode_zip(zip_code)
            result = compute_index_for_location(lat, lon, radius)
            result['zip_code'] = zip_code

            return {
                'statusCode': 200,
                'headers': headers,
                'body': json.dumps(result)
            }

        elif path == '/api/health' or path == '/health':
            # Health check
            return {
                'statusCode': 200,
                'headers': headers,
                'body': json.dumps({
                    "status": "healthy",
                    "service": "Waffle House Index API",
                    "version": "2.0.0",
                    "runtime": "AWS Lambda"
                })
            }

        elif path == '/api/refresh':
            # Force refresh of cache (useful for scheduled events)
            locations = fetch_locations_from_source()

            # Store in cache with TTL
            table.put_item(Item={
                'id': 'locations_cache',
                'locations': locations,
                'ttl': int(time.time()) + CACHE_TTL,
                'updated_at': datetime.utcnow().isoformat()
            })

            return {
                'statusCode': 200,
                'headers': headers,
                'body': json.dumps({
                    "message": "Cache refreshed successfully",
                    "locations_count": len(locations),
                    "updated_at": datetime.utcnow().isoformat()
                })
            }

        else:
            return {
                'statusCode': 404,
                'headers': headers,
                'body': json.dumps({"error": "Endpoint not found"})
            }

    except ValueError as e:
        return {
            'statusCode': 400,
            'headers': headers,
            'body': json.dumps({"error": str(e)})
        }
    except Exception as e:
        print(f"Error: {e}")
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({"error": "Internal server error"})
        }
