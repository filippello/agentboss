cask "focuspal" do
  version "0.2.0"
  sha256 "4555bced058082679ba3ea0aa0956262b7546d8b86815cdb987a3a0a213a0ea9"

  url "https://github.com/filippello/focuspal/releases/download/v#{version}/FocusPal-v#{version}-arm64.zip"
  name "FocusPal"
  desc "Hackable AI dev companion for Claude Code (menu bar pixel-art frog)"
  homepage "https://github.com/filippello/focuspal"

  depends_on macos: ">= :ventura"
  depends_on arch: :arm64

  app "FocusPal.app"

  zap trash: [
    "~/.focuspal",
    "~/.claude/focuspal",
    "~/Library/Preferences/com.filippello.focuspal.plist",
    "~/Library/Saved Application State/com.filippello.focuspal.savedState",
  ]
end
