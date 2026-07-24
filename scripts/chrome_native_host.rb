#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "optparse"
require "pathname"
require "tempfile"

HOST_NAME = "dev.topher.chrome_bridge"
HELPER_NAME = "TopherChromeBridgeHost"
PACKAGED_EXTENSION_ID = "mhbppdheppcibhhcnhnfockmfpcfhndj"
EXTENSION_ID_PATTERN = /\A[a-p]{32}\z/
DEFAULT_DESTINATION = File.expand_path(
  "~/Library/Application Support/Google/Chrome/NativeMessagingHosts"
)

def fail_helper(message)
  warn "Chrome native host helper failed: #{message}"
  exit 1
end

def parse_options(arguments)
  options = {destination: DEFAULT_DESTINATION, extension_id: PACKAGED_EXTENSION_ID}
  parser = OptionParser.new do |value|
    value.banner = "Usage: scripts/chrome_native_host.rb COMMAND --app /absolute/Topher.app"
    value.on("--extension-id ID", "Override for verification; must match the packaged ID") do |id|
      options[:extension_id] = id
    end
    value.on("--app PATH", "Absolute path to the built Topher.app") do |path|
      options[:app] = path
    end
    value.on("--destination PATH", "Override registration directory (tests only)") do |path|
      options[:destination] = path
    end
  end
  parser.parse!(arguments)
  command = arguments.shift
  fail_helper(parser.to_s) unless %w[check install uninstall].include?(command)
  fail_helper("unexpected arguments: #{arguments.join(" ")}") unless arguments.empty?
  [command, options]
rescue OptionParser::ParseError => error
  fail_helper(error.message)
end

def validate_inputs!(options)
  extension_id = options[:extension_id]
  fail_helper("--extension-id must contain exactly 32 lowercase letters a-p") unless
    extension_id&.match?(EXTENSION_ID_PATTERN)
  fail_helper("--extension-id must match Topher's packaged extension") unless
    extension_id == PACKAGED_EXTENSION_ID

  app = options[:app]
  fail_helper("--app must be an absolute path") unless app && Pathname.new(app).absolute?
  fail_helper("Topher.app must be a real directory, not a symlink") unless
    File.directory?(app) && !File.lstat(app).symlink?

  helper = File.join(app, "Contents", "Helpers", HELPER_NAME)
  fail_helper("bundled native host is missing: #{helper}") unless File.file?(helper)
  helper_information = File.lstat(helper)
  fail_helper("bundled native host must not be a symlink") if helper_information.symlink?
  fail_helper("bundled native host has an unexpected owner") unless
    [0, Process.euid].include?(helper_information.uid)
  fail_helper("bundled native host is writable by group or others") unless
    (helper_information.mode & 0o022).zero?
  fail_helper("bundled native host is not executable") unless File.executable?(helper)

  destination = options.fetch(:destination)
  fail_helper("--destination must be an absolute path") unless Pathname.new(destination).absolute?

  options.merge(
    app: File.realpath(app),
    helper: File.realpath(helper),
    destination: File.expand_path(destination)
  )
end

def ensure_secure_destination!(destination)
  FileUtils.mkdir_p(destination, mode: 0o700)
  information = File.lstat(destination)
  fail_helper("registration directory must not be a symlink") if information.symlink?
  fail_helper("registration directory must be owned by the current user") unless
    information.uid == Process.euid
  File.chmod(0o700, destination)
end

def expected_manifest(options)
  {
    "name" => HOST_NAME,
    "description" => "Topher bounded Chrome context bridge",
    "path" => options.fetch(:helper),
    "type" => "stdio",
    "allowed_origins" => ["chrome-extension://#{options.fetch(:extension_id)}/"]
  }
end

def manifest_path(options)
  File.join(options.fetch(:destination), "#{HOST_NAME}.json")
end

def read_manifest!(path)
  information = File.lstat(path)
  fail_helper("registration manifest must be a regular file, not a symlink") unless
    information.file? && !information.symlink?
  fail_helper("registration manifest must be owned by the current user") unless
    information.uid == Process.euid
  fail_helper("registration manifest is writable by group or others") unless
    (information.mode & 0o022).zero?
  fail_helper("registration manifest exceeds 8192 bytes") if information.size > 8_192
  JSON.parse(File.read(path, 8_193))
rescue Errno::ENOENT
  fail_helper("registration manifest is not installed: #{path}")
rescue JSON::ParserError, ArgumentError => error
  fail_helper("registration manifest is invalid: #{error.message}")
end

command, raw_options = parse_options(ARGV)
options = validate_inputs!(raw_options)
path = manifest_path(options)
expected = expected_manifest(options)

case command
when "install"
  ensure_secure_destination!(options.fetch(:destination))
  if File.exist?(path) || File.symlink?(path)
    existing = read_manifest!(path)
    fail_helper("existing manifest does not match this app and extension") unless existing == expected
  end

  Tempfile.create([HOST_NAME, ".json"], options.fetch(:destination)) do |temporary|
    temporary.chmod(0o600)
    temporary.write(JSON.pretty_generate(expected) + "\n")
    temporary.flush
    temporary.fsync
    File.rename(temporary.path, path)
  end
  File.chmod(0o600, path)
  puts "Installed #{path} for chrome-extension://#{options.fetch(:extension_id)}/"
when "check"
  actual = read_manifest!(path)
  fail_helper("manifest does not exactly match this app and extension") unless actual == expected
  fail_helper("registered helper path is not absolute") unless Pathname.new(actual.fetch("path")).absolute?
  puts "Chrome native host registration is valid: #{path}"
when "uninstall"
  actual = read_manifest!(path)
  fail_helper("refusing to remove a manifest that does not exactly match") unless actual == expected
  File.delete(path)
  puts "Removed #{path}"
end
