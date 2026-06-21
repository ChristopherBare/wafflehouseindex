"""
AWS Lambda handler for Waffle House Index API
Optimized for performance and cost with DynamoDB caching
"""

import json
import math
import time
import os
import gzip
import base64
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
    """Fetch all Waffle House locations from the Where2GetIt/SOCI locator API."""
    API_URL = "https://locations.wafflehouse.com/rest/locatorsearch"
    APPKEY = "67D5833A-80B5-4F9E-9C2B-9E7BAA634C27"

    # Center of the continental US with a radius large enough to cover all locations
    payload = json.dumps({
        "request": {
            "appkey": APPKEY,
            "formdata": {
                "dataview": "store_default",
                "limit": 5000,
                "geolocs": {"geoloc": [{"latitude": "39.5", "longitude": "-98.35"}]},
                "searchradius": "5000",
            }
        }
    }).encode()

    req = urllib.request.Request(
        API_URL,
        data=payload,
        headers={
            "Content-Type": "application/json",
            "User-Agent": UA,
            "Referer": "https://locations.wafflehouse.com/",
        },
        method="POST",
    )

    with urllib.request.urlopen(req, timeout=30) as resp:
        if resp.status != 200:
            raise RuntimeError(f"Locator API returned status {resp.status}")
        data = json.loads(resp.read().decode())

    collection = data.get("response", {}).get("collection", [])
    print(f"Fetched {len(collection)} locations from API")

    out = []
    for loc in collection:
        id_ = str(loc.get("clientkey") or loc.get("uid") or "").strip()
        if not id_:
            continue

        try:
            lat = float(loc["latitude"])
            lon = float(loc["longitude"])
        except (KeyError, TypeError, ValueError):
            continue

        name = loc.get("name") or None
        city = (loc.get("city") or "").title() or None
        state = loc.get("state") or None

        # opening_status lives inside the nested location object
        location_obj = loc.get("location") or {}
        opening_status = ""
        if isinstance(location_obj, dict):
            opening_status = (location_obj.get("opening_status") or "").lower()

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

    print(f"Parsed {len(out)} valid locations")
    return out


def _compress(data: list) -> str:
    raw = json.dumps(data).encode()
    compressed = gzip.compress(raw, compresslevel=6)
    return base64.b64encode(compressed).decode()


def _decompress(blob: str) -> list:
    compressed = base64.b64decode(blob)
    raw = gzip.decompress(compressed)
    return json.loads(raw)


def get_locations_from_cache() -> List[Dict]:
    """Get locations from DynamoDB cache or fetch fresh data."""
    try:
        response = table.get_item(Key={'id': 'locations_cache'})
        if 'Item' in response:
            item = response['Item']
            if item.get('ttl', 0) > int(time.time()):
                print("Using cached location data")
                blob = item.get('locations_gz')
                if blob:
                    return _decompress(blob)
                return item.get('locations', [])
        print("Cache miss or expired, fetching fresh data")
    except Exception as e:
        print(f"Error reading from cache: {e}")

    locations = fetch_locations_from_source()

    try:
        blob = _compress(locations)
        print(f"Compressed {len(locations)} locations to {len(blob)} bytes")
        table.put_item(Item={
            'id': 'locations_cache',
            'locations_gz': blob,
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
