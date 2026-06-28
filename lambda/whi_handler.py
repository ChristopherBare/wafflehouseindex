"""
AWS Lambda handler for Waffle House Index API
Robust persistent storage with failsafe mechanisms
"""

import json
import math
import time
import os
import boto3
from typing import List, Dict, Any, Tuple
from datetime import datetime
import urllib.request
from decimal import Decimal

# DynamoDB client
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ.get('DYNAMODB_TABLE', 'whi-locations'))

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

def _fetch_region(lat: float, lon: float, radius: int) -> List[Dict]:
    """Fetch locations for a single region."""
    API_URL = "https://locations.wafflehouse.com/rest/locatorsearch"
    APPKEY = "67D5833A-80B5-4F9E-9C2B-9E7BAA634C27"
    payload = json.dumps({
        "request": {
            "appkey": APPKEY,
            "formdata": {
                "dataview": "store_default",
                "limit": 500,
                "geolocs": {"geoloc": [{"latitude": str(lat), "longitude": str(lon)}]},
                "searchradius": str(radius),
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
            raise RuntimeError(f"Locator API returned {resp.status}")
        data = json.loads(resp.read().decode())

    out = []
    timestamp = datetime.utcnow().isoformat()
    for loc in data.get("response", {}).get("collection", []):
        id_ = str(loc.get("clientkey") or loc.get("uid") or "").strip()
        if not id_: continue
        try:
            lat_ = float(loc["latitude"])
            lon_ = float(loc["longitude"])
        except (KeyError, TypeError, ValueError): continue

        location_obj = loc.get("location") or {}
        opening_status = (location_obj.get("opening_status") or "").lower() if isinstance(location_obj, dict) else ""
        status = "Closed" if opening_status in ("temporarily_closed", "permanently_closed", "closed") else "Open"

        address1 = (loc.get("address1") or "").strip()
        address2 = (loc.get("address2") or "").strip()
        full_address = f"{address1} {address2}".strip()

        out.append({
            "id": id_,
            "name": loc.get("name") or None,
            "address": full_address or None,
            "city": (loc.get("city") or "").title() or None,
            "state": loc.get("state") or None,
            "zip": loc.get("postalcode") or None,
            "phone": loc.get("phone") or None,
            "status": status,
            "lat": lat_,
            "lon": lon_,
            "last_updated": timestamp
        })
    return out

def fetch_all_from_source() -> List[Dict]:
    """Fetch all Waffle House locations by querying several regional centers."""
    regions = [
        (33.75,  -84.39, 300), (32.08,  -81.09, 300), (27.95,  -82.46, 300),
        (25.76,  -80.19, 300), (30.33,  -81.66, 300), (35.23,  -80.84, 300),
        (35.78,  -78.64, 300), (36.17,  -86.78, 300), (35.15,  -90.05, 300),
        (33.52,  -86.81, 300), (32.30,  -90.18, 300), (29.95,  -90.07, 300),
        (29.76,  -95.37, 300), (32.78,  -96.80, 300), (39.50,  -98.35, 600),
        (38.90,  -77.03, 300), (39.96,  -82.99, 300),
    ]
    seen = {}
    for lat, lon, radius in regions:
        try:
            locs = _fetch_region(lat, lon, radius)
            print(f"Fetched {len(locs)} from region ({lat},{lon})")
            for loc in locs: seen[loc["id"]] = loc
        except Exception as e:
            print(f"Error fetching region ({lat},{lon}): {e}")
    return list(seen.values())

def sync_to_db(locations: List[Dict]):
    """Sync locations to DynamoDB using batch writer."""
    print(f"Syncing {len(locations)} locations to DynamoDB...")
    try:
        with table.batch_writer() as batch:
            for loc in locations:
                # Convert floats to Decimal for DynamoDB
                item = json.loads(json.dumps(loc), parse_float=Decimal)
                batch.put_item(Item=item)
        print("Sync complete.")
    except Exception as e:
        print(f"Error during batch sync: {e}")

def get_all_from_db() -> List[Dict]:
    """Scan DynamoDB to retrieve all stored locations."""
    print("Scanning DynamoDB for all locations...")
    try:
        response = table.scan()
        items = response.get('Items', [])
        while 'LastEvaluatedKey' in response:
            response = table.scan(ExclusiveStartKey=response['LastEvaluatedKey'])
            items.extend(response.get('Items', []))

        # Filter out the old 'locations_cache' item if it exists
        clean_items = [i for i in items if i.get('id') != 'locations_cache']
        print(f"Found {len(clean_items)} locations in DB.")
        return clean_items
    except Exception as e:
        print(f"Error scanning DB: {e}")
        return []

def get_locations_with_failsafe() -> Tuple[List[Dict], str]:
    """Get locations from source, or fallback to DB if source fails."""
    # PERFORMANCE OPTIMIZATION:
    # User requests serve from DynamoDB for speed (< 1s).
    # Background cron job handles the slow 48s scraper.

    db_items = get_all_from_db()

    # If DB has data, return it immediately (even if slightly stale)
    if db_items and len(db_items) > 100:
        print("Serving from persistent DynamoDB storage.")
        # Helper to convert Decimal back to float for API response
        def decimal_to_float(obj):
            if isinstance(obj, Decimal):
                return float(obj)
            raise TypeError

        clean_locations = json.loads(json.dumps(db_items, default=decimal_to_float))
        return clean_locations, "database"

    # Only attempt live fetch if DB is empty (First run or wiped)
    print("Database is empty, attempting emergency live fetch...")
    try:
        locations = fetch_all_from_source()
        if not locations or len(locations) < 100:
            raise RuntimeError(f"Scraper returned suspiciously low results: {len(locations)}")

        sync_to_db(locations)
        return locations, "live_emergency"
    except Exception as e:
        print(f"Emergency live fetch failed: {e}.")
        return [], "error"

def compute_index_for_location(lat: float, lon: float, radius_miles: float = 50.0) -> Dict[str, Any]:
    """Compute the Waffle House Index for a given location."""
    all_locs, source = get_locations_with_failsafe()

    # Filter by distance
    details = []
    for loc in all_locs:
        if 'lat' not in loc or 'lon' not in loc: continue

        dmi = distance_miles(lat, lon, float(loc['lat']), float(loc['lon']))
        if dmi <= radius_miles:
            loc_with_dist = loc.copy()
            loc_with_dist['distance_mi'] = dmi
            details.append(loc_with_dist)

    # Sort by distance
    details.sort(key=lambda x: x.get('distance_mi', 0.0))

    total = len(details)
    open_ct = sum(1 for d in details if d.get('status') == "Open")
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
        "data_source": source,
        "as_of": datetime.utcnow().isoformat()
    }

def lambda_handler(event, context):
    """Main Lambda handler for API Gateway events."""

    # Enable CORS
    headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,Accept,Origin,User-Agent',
        'Access-Control-Allow-Methods': 'GET,OPTIONS'
    }

    # Handle OPTIONS for CORS preflight
    if event.get('httpMethod') == 'OPTIONS':
        return {
            'statusCode': 200,
            'headers': headers,
            'body': ''
        }

    # Handle Scheduled Refresh from EventBridge
    if event.get('isScheduled') is True:
        print("Starting scheduled data refresh...")
        try:
            locations = fetch_all_from_source()
            if locations:
                sync_to_db(locations)
                return {'statusCode': 200, 'body': json.dumps({"status": "Scheduled refresh complete", "count": len(locations)})}
        except Exception as e:
            print(f"Scheduled refresh failed: {e}")
            return {'statusCode': 500, 'body': str(e)}

    path = event.get('path', '/')
    query_params = event.get('queryStringParameters', {}) or {}

    try:
        # Route handling
        if path.startswith('/api/index/coordinates'):
            # Get by coordinates
            lat = float(query_params.get('lat'))
            lon = float(query_params.get('lon'))
            radius = float(query_params.get('radius', 50))

            if not (-90 <= lat <= 90) or not (-180 <= lon <= 180):
                return {'statusCode': 400, 'headers': headers, 'body': json.dumps({"error": "Invalid coordinates"})}

            result = compute_index_for_location(lat, lon, radius)
            return {'statusCode': 200, 'headers': headers, 'body': json.dumps(result)}

        elif path.startswith('/api/index/zip'):
            # Get by ZIP code
            zip_code = query_params.get('zip')
            if not zip_code or not (len(zip_code) == 5 and zip_code.isdigit()):
                return {'statusCode': 400, 'headers': headers, 'body': json.dumps({"error": "Invalid ZIP"})}

            radius = float(query_params.get('radius', 50))
            lat, lon = geocode_zip(zip_code)
            result = compute_index_for_location(lat, lon, radius)
            result['zip_code'] = zip_code

            return {'statusCode': 200, 'headers': headers, 'body': json.dumps(result)}

        elif path == '/api/health' or path == '/health':
            return {
                'statusCode': 200,
                'headers': headers,
                'body': json.dumps({
                    "status": "healthy",
                    "service": "Waffle House Index API",
                    "version": "2.1.2",
                    "runtime": "AWS Lambda",
                    "persistent_storage": "enabled"
                })
            }

        elif path == '/api/refresh':
            locations = fetch_all_from_source()
            sync_to_db(locations)
            return {
                'statusCode': 200,
                'headers': headers,
                'body': json.dumps({
                    "message": "Persistent storage synced",
                    "count": len(locations),
                    "timestamp": datetime.utcnow().isoformat()
                })
            }

        else:
            return {'statusCode': 404, 'headers': headers, 'body': json.dumps({"error": "Not found"})}

    except Exception as e:
        print(f"Error: {e}")
        return {'statusCode': 500, 'headers': headers, 'body': json.dumps({"error": str(e)})}
