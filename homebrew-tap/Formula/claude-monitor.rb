class ClaudeMonitor < Formula
  desc "Floating macOS dashboard that monitors all active Claude Code sessions"
  homepage "https://github.com/muddled-design/ObservationDeck"
  url "https://github.com/muddled-design/ObservationDeck/archive/refs/tags/v1.1.0.tar.gz"
  sha256 "399582b319c1f179a303f93564d4a5514051b67d44086e3c3148918706e3798c"
  license "MIT"

  depends_on "xcodegen" => :build
  depends_on xcode: ["15.0", :build]
  depends_on macos: :sonoma

  def install
    system "xcodegen", "generate"
    system "xcodebuild",
           "-project", "ObservationDeck.xcodeproj",
           "-scheme", "ClaudeMonitor",
           "-configuration", "Release",
           "CODE_SIGN_IDENTITY=",
           "CODE_SIGNING_REQUIRED=NO",
           "CODE_SIGNING_ALLOWED=NO",
           "CONFIGURATION_BUILD_DIR=#{buildpath}/build"

    prefix.install "build/ClaudeMonitor.app"

    (share/"claude-monitor").mkpath
    cp "monitor-hook.sh", share/"claude-monitor/monitor-hook.sh"
    chmod 0755, share/"claude-monitor/monitor-hook.sh"

    cp "scripts/install-hooks.sh", share/"claude-monitor/install-hooks.sh"
    chmod 0755, share/"claude-monitor/install-hooks.sh"
  end

  def post_install
    hook_src = share/"claude-monitor/monitor-hook.sh"
    hook_dest = Pathname.new(Dir.home)/".claude/monitor-hook.sh"
    status_dir = Pathname.new(Dir.home)/".claude/monitor-status"
    settings_file = Pathname.new(Dir.home)/".claude/settings.json"

    hook_dest.dirname.mkpath
    status_dir.mkpath

    cp hook_src, hook_dest
    chmod 0755, hook_dest
    ohai "Installed hook script to #{hook_dest}"

    register_hooks(settings_file)

    ohai "Hooks installed! They will activate on your next Claude Code session."
  end

  def caveats
    app_path = prefix/"ClaudeMonitor.app"
    <<~EOS
      The app has been installed to:
        #{app_path}

      To launch, either:
        open #{app_path}

      Or add it to Login Items for auto-start.

      Claude Code hooks have been installed automatically.
      To remove hooks:  #{share}/claude-monitor/install-hooks.sh --uninstall
      To reinstall hooks: #{share}/claude-monitor/install-hooks.sh
    EOS
  end

  test do
    assert_predicate prefix/"ClaudeMonitor.app/Contents/MacOS/ClaudeMonitor", :executable?
    assert_predicate share/"claude-monitor/monitor-hook.sh", :exist?
  end

  private

  def register_hooks(settings_file)
    require "json"
    hook_command = "bash ~/.claude/monitor-hook.sh"
    events = %w[Stop Notification PreToolUse PostToolUse SubagentStart SubagentStop]

    settings = if settings_file.exist?
      JSON.parse(settings_file.read)
    else
      {}
    end

    hooks = settings["hooks"] || {}
    hook_entry = { "type" => "command", "command" => hook_command, "async" => true }
    changed = false

    events.each do |event|
      rules = hooks[event] || []

      found = rules.any? do |rule|
        (rule["hooks"] || []).any? { |h| h["command"] == hook_command }
      end

      unless found
        if rules.empty?
          rules << { "hooks" => [hook_entry] }
        else
          rules[0]["hooks"] ||= []
          rules[0]["hooks"] << hook_entry
        end
        hooks[event] = rules
        changed = true
      end
    end

    if changed
      settings["hooks"] = hooks
      settings_file.write(JSON.pretty_generate(settings))
      ohai "Registered hooks in #{settings_file}"
    else
      ohai "Hooks already registered in #{settings_file}"
    end
  end
end
