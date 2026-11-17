#!/bin/bash
# Writes build/voice-changer.rb, the Homebrew cask for build/VoiceChanger.zip. Needs VERSION.
set -euo pipefail
cd "$(dirname "$0")/.."

sha=$(shasum -a 256 build/VoiceChanger.zip | cut -d ' ' -f 1)

cat > build/voice-changer.rb <<CASK
cask "voice-changer" do
  version "${VERSION}"
  sha256 "${sha}"

  url "https://github.com/abaicus/voice-changer/releases/download/v#{version}/VoiceChanger.zip"
  name "Voice Changer"
  desc "Real-time voice changer that feeds a virtual microphone"
  homepage "https://abaic.us/voice-changer"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on cask: "blackhole-2ch"
  depends_on macos: :sonoma

  app "VoiceChanger.app"

  # Not signed with an Apple Developer ID, so Gatekeeper would block it. The
  # checksum is pinned above; this drops the quarantine flag on that download.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/VoiceChanger.app"]
  end

  uninstall quit: "local.voicechanger.app"

  zap trash: [
    "~/Library/Application Support/VoiceChanger",
    "~/Library/Preferences/local.voicechanger.app.plist",
  ]

  caveats <<~EOS
    Voice Changer sends your changed voice to BlackHole 2ch, which this cask
    installs. In Discord, Zoom, Google Meet or OBS pick "BlackHole 2ch" as the
    microphone.

    The build is not notarized by Apple. This cask has already cleared the
    quarantine flag for you, so it will just open.
  EOS
end
CASK
echo "Rendered build/voice-changer.rb"
