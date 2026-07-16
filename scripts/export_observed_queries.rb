#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require "securerandom"
require "time"

ROOT = File.expand_path("..", __dir__)
DEFAULT_INPUT = File.expand_path(
  "~/Library/Caches/dev.topher.app/TranscriptDiagnostics/transcript-diagnostics.json"
)
DEFAULT_DIRECTORY = File.join(ROOT, ".topher-local", "dogfood")
DEFAULT_OUTPUT = File.join(DEFAULT_DIRECTORY, "observed-queries.json")
LOCAL_ROOT = File.join(ROOT, ".topher-local")
MAXIMUM_FILE_BYTES = 1_048_576
MAXIMUM_ENTRIES = 500
MAXIMUM_IMPORTED_RECORD_IDS = 2_000
MAXIMUM_PHRASE_BYTES = 4_096

options = { include_dictation: false, input: DEFAULT_INPUT, output: DEFAULT_OUTPUT }
OptionParser.new do |parser|
  parser.banner = "Usage: scripts/export_observed_queries.rb [options]"
  parser.on("--include-dictation", "Intentionally retain free-form dictation") do
    options[:include_dictation] = true
  end
  parser.on("--input PATH", "Read another diagnostics file") do |path|
    options[:input] = File.expand_path(path)
  end
  parser.on("--output PATH", "Write another local output path") do |path|
    options[:output] = File.expand_path(path)
  end
  parser.on("-h", "--help", "Show this help") do
    puts parser
    exit
  end
end.parse!

def regular_owned_file!(path, allow_missing: false)
  return if allow_missing && !File.exist?(path) && !File.symlink?(path)

  stat = File.lstat(path)
  abort("Unsafe file path: #{path}") unless stat.file? && stat.uid == Process.uid && stat.nlink == 1
end

def owned_directory!(path)
  stat = File.lstat(path)
  abort("Unsafe directory path: #{path}") unless stat.directory? && stat.uid == Process.uid
  File.chmod(0o700, path)
end

def bounded_phrase(value)
  phrase = value.to_s.strip
  return nil if phrase.empty?

  bytes = 0
  phrase.each_char.with_object(String.new) do |character, result|
    size = character.bytesize
    break result if bytes + size > MAXIMUM_PHRASE_BYTES

    result << character
    bytes += size
  end
end

input = options.fetch(:input)
output = options.fetch(:output)
abort("Diagnostics file not found: #{input}") unless File.file?(input)
regular_owned_file!(input)
abort("Diagnostics file is too large") if File.size(input) > MAXIMUM_FILE_BYTES

diagnostics = JSON.parse(File.read(input, encoding: "UTF-8"))
records = diagnostics.fetch("records")
abort("Diagnostics records must be an array") unless records.is_a?(Array)

directory = File.dirname(output)
unless output.start_with?(LOCAL_ROOT + File::SEPARATOR)
  abort("Observed-query output must stay inside #{LOCAL_ROOT}")
end
[LOCAL_ROOT, directory].each do |path|
  if File.exist?(path) || File.symlink?(path)
    owned_directory!(path)
  else
    Dir.mkdir(path, 0o700)
    owned_directory!(path)
  end
end
regular_owned_file!(output, allow_missing: true)

existing_document = if File.file?(output)
  abort("Observed-query dataset is too large") if File.size(output) > MAXIMUM_FILE_BYTES
  parsed = JSON.parse(File.read(output, encoding: "UTF-8"))
  abort("Unsupported observed-query schema") unless parsed["schemaVersion"] == 1
  parsed
else
  { "queries" => [], "importedRecordIDs" => [] }
end
existing = existing_document.fetch("queries")
abort("Observed queries must be an array") unless existing.is_a?(Array)

queries = existing.each_with_object({}) do |entry, result|
  next unless entry.is_a?(Hash) && entry["key"].is_a?(String)
  result[entry.fetch("key")] = entry
end

allowed_sources = options[:include_dictation] ? %w[dictation manual voice] : %w[manual voice]
eligible_records = records.select do |record|
  record.is_a?(Hash) && allowed_sources.include?(record["source"])
end
imported_record_ids = Array(existing_document["importedRecordIDs"]).each_with_object({}) do |id, result|
  result[id] = true if id.is_a?(String)
end

# The first development version of this exporter did not retain an import
# ledger. Preserve its counts and mark the currently retained records imported
# instead of double-counting them on the first upgraded run.
if File.file?(output) && !existing_document.key?("importedRecordIDs")
  eligible_records.each { |record| imported_record_ids[record["id"]] = true }
end

eligible_records.each do |record|
  record_id = record["id"]
  next if record_id.is_a?(String) && imported_record_ids[record_id]
  phrase = bounded_phrase(record["transcript"])
  next unless phrase

  key = "#{record.fetch('source')}\u0000#{phrase.downcase.gsub(/\s+/, ' ')}"
  observed_at = record["recordedAt"].to_s
  entry = queries[key] ||= {
    "key" => key,
    "source" => record.fetch("source"),
    "phrase" => phrase,
    "firstObservedAt" => observed_at,
    "lastObservedAt" => observed_at,
    "observationCount" => 0,
    "outcomes" => {},
    "interpretationReasons" => {},
    "dictationInsertionMethods" => {},
    "dictationInsertionVerifications" => {},
    "dictationTargetRoles" => {},
    "unsupportedReasons" => {},
    "dictationFailureReasons" => {},
    "captureFailureReasons" => {},
    "actionIssueReasons" => {},
    "commandKinds" => {},
    "automaticFinalizationCount" => 0,
    "ratings" => {
      "transcriptCorrect" => 0,
      "transcriptIncorrect" => 0,
      "actionCorrect" => 0,
      "actionIncorrect" => 0
    },
    "appBuilds" => []
  }

  entry["lastObservedAt"] = [entry["lastObservedAt"].to_s, observed_at].max
  entry["firstObservedAt"] = [entry["firstObservedAt"].to_s, observed_at].reject(&:empty?).min
  entry["observationCount"] = entry["observationCount"].to_i + 1
  {
    "outcomes" => record["outcome"],
    "interpretationReasons" => record["interpretationReason"],
    "dictationInsertionMethods" => record.dig("dictationInsertionEvidence", "method"),
    "dictationInsertionVerifications" => record.dig(
      "dictationInsertionEvidence", "verification"
    ),
    "dictationTargetRoles" => record.dig("dictationInsertionEvidence", "target", "role"),
    "unsupportedReasons" => record["unsupportedReason"],
    "dictationFailureReasons" => record["dictationFailureReason"],
    "captureFailureReasons" => record["captureFailureReason"],
    "actionIssueReasons" => record["actionIssueReason"],
    "commandKinds" => record["commandKind"]
  }.each do |bucket, value|
    next if value.to_s.empty?
    entry[bucket] ||= {}
    entry[bucket][value] = entry[bucket].fetch(value, 0).to_i + 1
  end
  if record["maximumDurationReached"] == true
    entry["automaticFinalizationCount"] = entry["automaticFinalizationCount"].to_i + 1
  end
  entry["ratings"][record["transcriptWasAccurate"] ? "transcriptCorrect" : "transcriptIncorrect"] += 1 unless record["transcriptWasAccurate"].nil?
  entry["ratings"][record["actionWasCorrect"] ? "actionCorrect" : "actionIncorrect"] += 1 unless record["actionWasCorrect"].nil?
  build = [record["appVersion"], record["appBuild"]].compact.join(" (")
  build += ")" if build.include?(" (")
  entry["appBuilds"] = (Array(entry["appBuilds"]) + [build]).reject(&:empty?).uniq.last(12)
  imported_record_ids[record_id] = true if record_id.is_a?(String)
end

retained = queries.values.sort_by { |entry| entry["lastObservedAt"].to_s }.last(MAXIMUM_ENTRIES)
document = {
  "schemaVersion" => 1,
  "generatedAt" => Time.now.utc.iso8601,
  "includesDictation" => existing_document["includesDictation"] == true || options[:include_dictation],
  "importedRecordIDs" => imported_record_ids.keys.last(MAXIMUM_IMPORTED_RECORD_IDS),
  "queries" => retained
}
data = JSON.pretty_generate(document) + "\n"
abort("Observed-query dataset exceeds the file bound") if data.bytesize > MAXIMUM_FILE_BYTES

temporary = "#{output}.#{SecureRandom.hex(6)}.tmp"
begin
  File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
    file.write(data)
    file.flush
    file.fsync
  end
  File.rename(temporary, output)
  File.chmod(0o600, output)
  regular_owned_file!(output)
ensure
  File.delete(temporary) if File.exist?(temporary)
end

puts "Exported #{retained.length} observed query phrase(s) to #{output}"
puts "Dataset contains dictation: #{document['includesDictation'] ? 'yes' : 'no'}"
