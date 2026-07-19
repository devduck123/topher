#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "tmpdir"

ROOT = File.expand_path("..", __dir__)
HELPER = File.join(ROOT, "scripts/chrome_native_host.rb")
HOST_NAME = "dev.topher.chrome_bridge"
EXTENSION_ID = "abcdefghijklmnopabcdefghijklmnop"

class ChromeNativeHostHelperTest < Minitest::Test
  def setup
    @temporary_directory = Dir.mktmpdir("topher-chrome-host-test")
    @app = File.join(@temporary_directory, "Topher.app")
    @host = File.join(@app, "Contents/Helpers/TopherChromeBridgeHost")
    @destination = File.join(@temporary_directory, "NativeMessagingHosts")
    FileUtils.mkdir_p(File.dirname(@host))
    File.write(@host, "#!/bin/sh\nexit 0\n")
    File.chmod(0o755, @host)
  end

  def teardown
    FileUtils.remove_entry_secure(@temporary_directory)
  end

  def test_install_check_and_uninstall_exact_registration
    stdout, stderr, status = run_helper("install")
    assert status.success?, stderr
    assert_includes stdout, "Installed"

    path = File.join(@destination, "#{HOST_NAME}.json")
    document = JSON.parse(File.read(path))
    assert_equal HOST_NAME, document.fetch("name")
    assert_equal File.realpath(@host), document.fetch("path")
    assert_equal "stdio", document.fetch("type")
    assert_equal ["chrome-extension://#{EXTENSION_ID}/"], document.fetch("allowed_origins")
    assert_equal 0, File.stat(path).mode & 0o077

    _stdout, check_stderr, check_status = run_helper("check")
    assert check_status.success?, check_stderr

    _stdout, uninstall_stderr, uninstall_status = run_helper("uninstall")
    assert uninstall_status.success?, uninstall_stderr
    refute File.exist?(path)
  end

  def test_rejects_wildcard_uppercase_and_wrong_length_extension_ids
    ["*", EXTENSION_ID.upcase, "abc"].each do |identifier|
      _stdout, stderr, status = run_helper("install", extension_id: identifier)
      refute status.success?
      assert_includes stderr, "exactly 32 lowercase letters a-p"
    end
  end

  def test_refuses_to_replace_or_remove_a_different_registration
    FileUtils.mkdir_p(@destination)
    path = File.join(@destination, "#{HOST_NAME}.json")
    File.write(path, JSON.generate({"name" => HOST_NAME, "path" => "/tmp/other"}))
    File.chmod(0o600, path)

    _stdout, install_stderr, install_status = run_helper("install")
    refute install_status.success?
    assert_includes install_stderr, "does not match"

    _stdout, uninstall_stderr, uninstall_status = run_helper("uninstall")
    refute uninstall_status.success?
    assert File.exist?(path)
    assert_includes uninstall_stderr, "refusing to remove"
  end

  def test_rejects_symlinked_app_and_missing_helper
    linked_app = File.join(@temporary_directory, "Linked.app")
    File.symlink(@app, linked_app)
    _stdout, stderr, status = run_helper("install", app: linked_app)
    refute status.success?
    assert_includes stderr, "must be a real directory"

    File.delete(@host)
    _stdout, missing_stderr, missing_status = run_helper("install")
    refute missing_status.success?
    assert_includes missing_stderr, "bundled native host is missing"
  end

  def test_rejects_unsafe_helper_mode_and_oversized_manifest
    File.chmod(0o775, @host)
    _stdout, mode_stderr, mode_status = run_helper("install")
    refute mode_status.success?
    assert_includes mode_stderr, "writable by group or others"

    File.chmod(0o755, @host)
    _stdout, install_stderr, install_status = run_helper("install")
    assert install_status.success?, install_stderr
    path = File.join(@destination, "#{HOST_NAME}.json")
    File.open(path, "a") { |file| file.write(" " * 8_192) }
    _stdout, size_stderr, size_status = run_helper("check")
    refute size_status.success?
    assert_includes size_stderr, "exceeds 8192 bytes"
  end

  private def run_helper(command, extension_id: EXTENSION_ID, app: @app)
    Open3.capture3(
      "ruby",
      HELPER,
      command,
      "--extension-id",
      extension_id,
      "--app",
      app,
      "--destination",
      @destination
    )
  end
end
