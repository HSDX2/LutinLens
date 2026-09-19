#!/usr/bin/env bash
set -euo pipefail

# Installs the vendored threeegl.aar into the local Maven repository (~/.m2)
# so the flutter_gl plugin can depend on it via Maven coordinates.

REPO_ROOT="$(cd "$(dirname "$0")"/.. && pwd)"
AAR_PATH_DEFAULT="$REPO_ROOT/third_party/flutter_gl-0.0.21/android/libs/aars/threeegl.aar"

AAR_PATH="${1:-$AAR_PATH_DEFAULT}"
GROUP_ID="${GROUP_ID:-com.threeegl}"
ARTIFACT_ID="${ARTIFACT_ID:-threeegl}"
VERSION="${VERSION:-0.0.1}"

if [[ ! -f "$AAR_PATH" ]]; then
  echo "AAR not found: $AAR_PATH" >&2
  exit 1
fi

echo "Installing $AAR_PATH to mavenLocal as $GROUP_ID:$ARTIFACT_ID:$VERSION ..."
mvn -q install:install-file \
  -Dfile="$AAR_PATH" \
  -DgroupId="$GROUP_ID" \
  -DartifactId="$ARTIFACT_ID" \
  -Dversion="$VERSION" \
  -Dpackaging=aar

echo "Done. Verify under ~/.m2/repository/${GROUP_ID//./\/}/$ARTIFACT_ID/$VERSION/"
