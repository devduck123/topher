#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"

DEFAULT_PATH = File.expand_path(
  "~/Library/Caches/dev.topher.app/TranscriptDiagnostics/transcript-diagnostics.json"
)

options = { path: DEFAULT_PATH }
OptionParser.new do |parser|
  parser.banner = "Usage: scripts/summarize_dogfood_diagnostics.rb [path]"
  parser.on("-h", "--help", "Show this help") do
    puts parser
    exit
  end
end.parse!
options[:path] = File.expand_path(ARGV.fetch(0, options[:path]))

abort("Diagnostics file not found: #{options[:path]}") unless File.file?(options[:path])

document = JSON.parse(File.read(options[:path], encoding: "UTF-8"))
records = document.fetch("records")
abort("Diagnostics records must be an array") unless records.is_a?(Array)

def counts(records, key)
  records.each_with_object(Hash.new(0)) do |record, result|
    value = record[key]
    result[value || "not recorded"] += 1
  end.sort_by { |name, _count| name.to_s }
end

def percentage(numerator, denominator)
  return "not rated" if denominator.zero?

  format("%.1f%% (%d/%d)", 100.0 * numerator / denominator, numerator, denominator)
end

def percentile(values, percentile)
  return nil if values.empty?

  sorted = values.sort
  rank = [(percentile * sorted.length).ceil - 1, 0].max
  sorted.fetch(rank)
end

def print_counts(label, values)
  puts label
  values.each { |name, count| puts "  #{name}: #{count}" }
end

def print_summary(title, records)
  puts title
  puts "Records: #{records.length}"
  print_counts("Sources:", counts(records, "source"))
  print_counts("Outcomes:", counts(records, "outcome"))
  unsupported_records = records.select { |record| record["unsupportedReason"] }
  print_counts("Unsupported reasons:", counts(unsupported_records, "unsupportedReason"))
  dictation_failure_records = records.select { |record| record["dictationFailureReason"] }
  print_counts(
    "Dictation fallback reasons:",
    counts(dictation_failure_records, "dictationFailureReason")
  )
  capture_failure_records = records.select { |record| record["captureFailureReason"] }
  print_counts("Capture failure reasons:", counts(capture_failure_records, "captureFailureReason"))

  transcript_ratings = records
    .select { |record| !record["transcriptWasAccurate"].nil? }
    .map { |record| record["transcriptWasAccurate"] }
  action_ratings = records
    .select { |record| !record["actionWasCorrect"].nil? }
    .map { |record| record["actionWasCorrect"] }
  puts "Feedback:"
  transcript_accuracy = percentage(transcript_ratings.count(true), transcript_ratings.length)
  action_correctness = percentage(action_ratings.count(true), action_ratings.length)
  puts "  transcript accurate: #{transcript_accuracy}"
  puts "  action/insertion correct: #{action_correctness}"
  issue_records = records.select { |record| record["actionIssueReason"] }
  print_counts("Action/insertion issue reasons:", counts(issue_records, "actionIssueReason"))

  automatic_finalizations = records.count { |record| record["maximumDurationReached"] == true }
  puts "Automatic maximum-duration finalizations: #{automatic_finalizations}"

  interpreted = records.count { |record| record["interpretedTranscript"] }
  puts "Interpreted/formatted text changes: #{interpreted}/#{records.length}"
  interpretation_records = records.select { |record| record["interpretationReason"] }
  print_counts(
    "Interpretation/polish reasons:",
    counts(interpretation_records, "interpretationReason")
  )

  timings = {
    "hold to listening" => "holdToListeningMilliseconds",
    "listening to first text" => "listeningToFirstTranscriptMilliseconds",
    "stop to final" => "keyUpToFinalMilliseconds",
    "request processing" => "processingDurationMilliseconds",
  }
  puts "Timing (milliseconds):"
  timings.each do |label, key|
    values = records.map { |record| record[key] }.compact
    next if values.empty?

    puts "  #{label}: p50 #{percentile(values, 0.50)}, p95 #{percentile(values, 0.95)}, n #{values.length}"
  end
end

puts "Topher dogfood diagnostics"
latest_session_record = records.reverse.find { |record| record["launchSessionID"] }
if latest_session_record
  latest_session_id = latest_session_record.fetch("launchSessionID")
  latest_session_records = records.select do |record|
    record["launchSessionID"] == latest_session_id
  end
  version = latest_session_record["appVersion"] || "unknown"
  build = latest_session_record["appBuild"] || "unknown"
  print_summary("Latest launch session (version #{version}, build #{build})", latest_session_records)
else
  puts "Latest launch session: not recorded (pre-Build-7 records)"
end

puts
print_summary("All retained history", records)
session_records = records.select { |record| record["launchSessionID"] }
session_count = session_records.map { |record| record["launchSessionID"] }.uniq.length
if session_records.empty?
  puts "Launch sessions: not recorded"
else
  puts "Launch sessions: #{session_count} (recorded on #{session_records.length}/#{records.length} requests)"
end
