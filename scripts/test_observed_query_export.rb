#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "securerandom"
require "tmpdir"

ROOT = File.expand_path("..", __dir__)
LOCAL_ROOT = File.join(ROOT, ".topher-local")
EXPORTER = File.join(__dir__, "export_observed_queries.rb")

def assert(condition, message)
  abort("Observed-query exporter test failed: #{message}") unless condition
end

def run_export(*arguments)
  stdout, stderr, status = Open3.capture3(RbConfig.ruby, EXPORTER, *arguments)
  [stdout, stderr, status]
end

begin
if File.exist?(LOCAL_ROOT) || File.symlink?(LOCAL_ROOT)
  stat = File.lstat(LOCAL_ROOT)
  assert(stat.directory? && stat.uid == Process.uid, "unsafe .topher-local directory")
else
  Dir.mkdir(LOCAL_ROOT, 0o700)
end
File.chmod(0o700, LOCAL_ROOT)

test_directory = File.join(
  LOCAL_ROOT,
  "exporter-test-#{Process.pid}-#{SecureRandom.hex(4)}"
)
Dir.mkdir(test_directory, 0o700)

Dir.mktmpdir("topher-exporter-input-") do |input_directory|
  input = File.join(input_directory, "diagnostics.json")
  output = File.join(test_directory, "observed-queries.json")
  diagnostics = {
    "schemaVersion" => 1,
    "records" => [
      {
        "id" => "11111111-1111-1111-1111-111111111111",
        "source" => "voice",
        "transcript" => "Go to eBay",
        "recordedAt" => "2026-07-16T00:00:00Z",
        "outcome" => "capabilitySucceeded",
        "interpretationReason" => "dictationDisfluencyCleanup",
        "commandKind" => "openWebsite",
        "actionWasCorrect" => false,
        "actionIssueReason" => "wrongDestination",
        "maximumDurationReached" => true,
        "appVersion" => "0.4.0",
        "appBuild" => "10"
      },
      {
        "id" => "22222222-2222-2222-2222-222222222222",
        "source" => "dictation",
        "transcript" => "private prose excluded by default",
        "recordedAt" => "2026-07-16T00:01:00Z",
        "outcome" => "dictationInserted",
        "dictationFailureReason" => "wrongField",
        "dictationInsertionEvidence" => {
          "method" => "wholeValue",
          "verification" => "contentAndCaret",
          "target" => {
            "role" => "textArea",
            "canSetSelectedText" => true,
            "canSetSelectedRange" => true,
            "canSetValue" => true
          }
        },
        "appVersion" => "0.4.0",
        "appBuild" => "10"
      }
    ]
  }
  File.write(input, JSON.generate(diagnostics), mode: "w", perm: 0o600)

  stdout, stderr, status = run_export("--input", input, "--output", output)
  assert(status.success?, "default export failed: #{stderr}")
  assert(stdout.include?("Dataset contains dictation: no"), "default sensitivity summary")
  document = JSON.parse(File.read(output, encoding: "UTF-8"))
  assert(document["includesDictation"] == false, "dictation must default off")
  assert(document.fetch("queries").length == 1, "only the command should be exported")
  command = document.fetch("queries").first
  assert(command["observationCount"] == 1, "command observation count")
  assert(
    command.dig("interpretationReasons", "dictationDisfluencyCleanup") == 1,
    "fixed polish metadata"
  )
  assert(command.dig("actionIssueReasons", "wrongDestination") == 1, "fixed issue metadata")
  assert(command["automaticFinalizationCount"] == 1, "automatic finalization metadata")
  assert(File.stat(output).mode & 0o777 == 0o600, "output file mode")
  assert(File.stat(test_directory).mode & 0o777 == 0o700, "output directory mode")

  _, stderr, status = run_export("--input", input, "--output", output)
  assert(status.success?, "repeat export failed: #{stderr}")
  repeated = JSON.parse(File.read(output, encoding: "UTF-8"))
  assert(repeated.dig("queries", 0, "observationCount") == 1, "repeat import must be idempotent")

  stdout, stderr, status = run_export(
    "--include-dictation",
    "--input", input,
    "--output", output
  )
  assert(status.success?, "explicit dictation export failed: #{stderr}")
  assert(stdout.include?("Dataset contains dictation: yes"), "sensitivity summary after opt-in")
  with_dictation = JSON.parse(File.read(output, encoding: "UTF-8"))
  assert(with_dictation["includesDictation"] == true, "dictation opt-in must remain visible")
  assert(with_dictation.fetch("queries").length == 2, "explicit dictation export")
  dictation = with_dictation.fetch("queries").find { |entry| entry["source"] == "dictation" }
  assert(dictation.dig("dictationInsertionMethods", "wholeValue") == 1, "insertion method")
  assert(
    dictation.dig("dictationInsertionVerifications", "contentAndCaret") == 1,
    "insertion verification"
  )
  assert(dictation.dig("dictationTargetRoles", "textArea") == 1, "target role")

  outside = File.join(input_directory, "outside.json")
  File.write(outside, "unchanged", mode: "w", perm: 0o600)
  unsafe_output = File.join(test_directory, "unsafe.json")
  File.symlink(outside, unsafe_output)
  _, _, status = run_export("--input", input, "--output", unsafe_output)
  assert(!status.success?, "symlinked output must be rejected")
  assert(File.read(outside) == "unchanged", "symlink target must remain unchanged")
end

puts "Observed-query exporter tests passed"
ensure
  if defined?(test_directory) && File.exist?(test_directory) && !File.symlink?(test_directory)
    FileUtils.remove_entry(test_directory)
  end
end
