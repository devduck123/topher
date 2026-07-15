#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

REPOSITORY_ROOT = File.expand_path("..", __dir__)
ROOT_LOCKFILE = File.join(REPOSITORY_ROOT, "Package.resolved")
XCODE_LOCKFILE = File.join(
  REPOSITORY_ROOT,
  "Topher.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
)
MANIFEST_FILE = File.join(REPOSITORY_ROOT, "Package.swift")
PROJECT_FILE = File.join(REPOSITORY_ROOT, "Topher.xcodeproj/project.pbxproj")
KEYBOARD_SHORTCUTS_IDENTITY = "keyboardshortcuts"

def fail_check(message)
  warn "Dependency parity check failed: #{message}"
  exit 1
end

def normalized_pins(path)
  document = JSON.parse(File.read(path))
  pins = document.fetch("pins")

  pins.map do |pin|
    state = pin.fetch("state")
    normalized = {
      "identity" => pin.fetch("identity"),
      "location" => pin.fetch("location"),
      "version" => state["version"],
      "revision" => state["revision"]
    }

    missing_fields = normalized.select { |_key, value| value.nil? || value.empty? }.keys
    unless missing_fields.empty?
      fail_check("#{path} has a pin missing #{missing_fields.join(", ")}")
    end

    normalized
  end.sort_by { |pin| [pin.fetch("identity"), pin.fetch("location")] }
rescue Errno::ENOENT, JSON::ParserError, KeyError, TypeError => error
  fail_check("could not read #{path}: #{error.message}")
end

def keyboard_shortcuts_reference(project)
  start_lines = project.lines.each_index.select do |index|
    project.lines[index].match?(
      /XCRemoteSwiftPackageReference "KeyboardShortcuts" \*\/ = \{/
    )
  end

  unless start_lines.length == 1
    fail_check(
      "expected exactly one KeyboardShortcuts XCRemoteSwiftPackageReference, " \
      "found #{start_lines.length}"
    )
  end

  lines = project.lines
  block = []
  depth = 0

  lines[start_lines.first..].each do |line|
    block << line
    depth += line.count("{")
    depth -= line.count("}")
    break if depth.zero?
  end

  fail_check("could not parse the KeyboardShortcuts package reference") unless depth.zero?

  text = block.join
  repository_url = text[/repositoryURL\s*=\s*"([^"]+)"\s*;/, 1]
  minimum_version = text[/minimumVersion\s*=\s*([^;\s]+)\s*;/, 1]

  if repository_url.nil? || minimum_version.nil?
    fail_check("KeyboardShortcuts package reference is missing repositoryURL or minimumVersion")
  end

  {"location" => repository_url, "minimum_version" => minimum_version}
end

def package_identity(location)
  location
    .sub(/[?#].*\z/, "")
    .sub(%r{/+\z}, "")
    .sub(/\.git\z/i, "")
    .split("/")
    .last
    .to_s
    .downcase
end

def keyboard_shortcuts_manifest_declaration(manifest)
  declarations = manifest.scan(/\.package\s*\((.*?)\)/m).map(&:first)

  candidates = declarations.each_with_object([]) do |arguments, matches|
    urls = arguments.scan(/\burl\s*:\s*"([^"]+)"/).flatten
    next if urls.empty?
    next unless urls.any? { |url| package_identity(url) == KEYBOARD_SHORTCUTS_IDENTITY }

    from_versions = arguments.scan(/\bfrom\s*:\s*"([^"]+)"/).flatten
    if urls.length != 1 || from_versions.length != 1
      fail_check(
        "KeyboardShortcuts declaration in Package.swift must contain exactly one " \
        "url and one from version"
      )
    end

    matches << {"location" => urls.first, "minimum_version" => from_versions.first}
  end

  unless candidates.length == 1
    fail_check(
      "expected exactly one KeyboardShortcuts .package(url:from:) declaration " \
      "in Package.swift, found #{candidates.length}"
    )
  end

  candidates.first
end

root_pins = normalized_pins(ROOT_LOCKFILE)
xcode_pins = normalized_pins(XCODE_LOCKFILE)

unless root_pins == xcode_pins
  fail_check(
    "Package.resolved files disagree on identity, location, version, or revision\n" \
    "root:  #{JSON.pretty_generate(root_pins)}\n" \
    "Xcode: #{JSON.pretty_generate(xcode_pins)}"
  )
end

keyboard_pins = root_pins.select do |pin|
  pin.fetch("identity").downcase == KEYBOARD_SHORTCUTS_IDENTITY
end

unless keyboard_pins.length == 1
  fail_check("expected exactly one KeyboardShortcuts pin, found #{keyboard_pins.length}")
end

keyboard_pin = keyboard_pins.first
manifest_declaration = keyboard_shortcuts_manifest_declaration(File.read(MANIFEST_FILE))
project_reference = keyboard_shortcuts_reference(File.read(PROJECT_FILE))

unless manifest_declaration.fetch("location") == keyboard_pin.fetch("location")
  fail_check(
    "KeyboardShortcuts URL in Package.swift " \
    "(#{manifest_declaration.fetch("location")}) does not match Package.resolved " \
    "(#{keyboard_pin.fetch("location")})"
  )
end

unless manifest_declaration.fetch("minimum_version") == keyboard_pin.fetch("version")
  fail_check(
    "KeyboardShortcuts from version in Package.swift " \
    "(#{manifest_declaration.fetch("minimum_version")}) does not match the resolved version " \
    "(#{keyboard_pin.fetch("version")})"
  )
end

unless project_reference.fetch("location") == keyboard_pin.fetch("location")
  fail_check(
    "KeyboardShortcuts repository URL differs between project.pbxproj " \
    "(#{project_reference.fetch("location")}) and Package.resolved " \
    "(#{keyboard_pin.fetch("location")})"
  )
end

unless project_reference.fetch("minimum_version") == keyboard_pin.fetch("version")
  fail_check(
    "KeyboardShortcuts minimumVersion in project.pbxproj " \
    "(#{project_reference.fetch("minimum_version")}) does not match the resolved version " \
    "(#{keyboard_pin.fetch("version")})"
  )
end

unless manifest_declaration.fetch("minimum_version") ==
       project_reference.fetch("minimum_version")
  fail_check(
    "KeyboardShortcuts minimum versions disagree between Package.swift " \
    "(#{manifest_declaration.fetch("minimum_version")}) and project.pbxproj " \
    "(#{project_reference.fetch("minimum_version")})"
  )
end

puts(
  "Dependency parity check passed: #{root_pins.length} Swift package pin(s); " \
  "Package.swift, Xcode, and both lockfiles use KeyboardShortcuts " \
  "#{keyboard_pin.fetch("version")} " \
  "(#{keyboard_pin.fetch("revision")})"
)
