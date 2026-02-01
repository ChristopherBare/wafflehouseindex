#!/bin/bash
# Auto-increment version based on commits since last tag
# Usage: ./scripts/get-version.sh [major|patch]

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( dirname "$SCRIPT_DIR" )"
VERSION_FILE="$PROJECT_DIR/.version"

# Parse version file
parse_version() {
  python3 - "$1" << 'PYTHON'
import sys, json
with open(sys.argv[1]) as f:
  v = json.load(f)
  print(f"{v['major']}.{v['minor']}.{v['patch']}")
PYTHON
}

get_commits_since_tag() {
  LAST_TAG=$(python3 -c "import json; print(json.load(open('$VERSION_FILE'))['last_tag'])")
  git rev-list --count "$LAST_TAG"..HEAD 2>/dev/null || echo "1"
}

increment_major() {
  python3 - "$VERSION_FILE" << 'PYTHON'
import sys, json
with open(sys.argv[1]) as f:
  v = json.load(f)
  v['major'] += 1
  v['minor'] = 0
  v['patch'] = 0
with open(sys.argv[1], 'w') as f:
  json.dump(v, f, indent=2)
PYTHON
}

increment_patch() {
  python3 - "$VERSION_FILE" << 'PYTHON'
import sys, json
with open(sys.argv[1]) as f:
  v = json.load(f)
  v['patch'] += 1
with open(sys.argv[1], 'w') as f:
  json.dump(v, f, indent=2)
PYTHON
}

# Get version from file
MAJOR=$(python3 -c "import json; print(json.load(open('$VERSION_FILE'))['major'])")
MINOR=$(python3 -c "import json; print(json.load(open('$VERSION_FILE'))['minor'])")
PATCH=$(python3 -c "import json; print(json.load(open('$VERSION_FILE'))['patch'])")

# Get build number (commits since last tag)
BUILD=$(get_commits_since_tag)

# Format output
VERSION_NAME="$MAJOR.$MINOR.$PATCH"
BUILD_NUMBER="$BUILD"

# If argument is 'major', increment major version
if [ "$1" == "major" ]; then
  increment_major
  MAJOR=$(python3 -c "import json; print(json.load(open('$VERSION_FILE'))['major'])")
  VERSION_NAME="$MAJOR.0.0"
  BUILD_NUMBER="1"
  echo "version_name=$VERSION_NAME"
  echo "build_number=$BUILD_NUMBER"
  echo "is_major_release=true"
elif [ "$1" == "patch" ]; then
  increment_patch
  PATCH=$(python3 -c "import json; print(json.load(open('$VERSION_FILE'))['patch'])")
  VERSION_NAME="$MAJOR.$MINOR.$PATCH"
  BUILD_NUMBER="1"
  echo "version_name=$VERSION_NAME"
  echo "build_number=$BUILD_NUMBER"
  echo "is_major_release=false"
else
  # Regular commit build
  echo "version_name=$VERSION_NAME"
  echo "build_number=$BUILD_NUMBER"
  echo "is_major_release=false"
fi
