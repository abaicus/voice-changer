#!/bin/bash
# Zips build/VoiceChanger.app into build/VoiceChanger.zip.
set -euo pipefail
cd "$(dirname "$0")/.."

ditto -c -k --keepParent build/VoiceChanger.app build/VoiceChanger.zip
echo "Packaged build/VoiceChanger.zip"
