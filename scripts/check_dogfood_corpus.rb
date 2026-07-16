#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"

ROOT = File.expand_path("..", __dir__)
DEFAULT_PATH = File.join(ROOT, "dogfood", "manual-corpus.json")
VALID_MODES = %w[assistant dictation].freeze
VALID_STATUSES = %w[contextRequired supported unsupported].freeze
MAXIMUM_CASES = 200
MAXIMUM_TEXT_BYTES = 4_096

options = { list: false, path: DEFAULT_PATH }
OptionParser.new do |parser|
  parser.banner = "Usage: scripts/check_dogfood_corpus.rb [options] [path]"
  parser.on("--list", "Print the manual checklist") { options[:list] = true }
  parser.on("--mode MODE", VALID_MODES, "Filter checklist by mode") do |mode|
    options[:mode] = mode
  end
  parser.on("--category CATEGORY", "Filter checklist by category") do |category|
    options[:category] = category
  end
  parser.on("-h", "--help", "Show this help") do
    puts parser
    exit
  end
end.parse!
options[:path] = File.expand_path(ARGV.fetch(0, options[:path]))

abort("Dogfood corpus not found: #{options[:path]}") unless File.file?(options[:path])
abort("Dogfood corpus is too large") if File.size(options[:path]) > 1_048_576

document = JSON.parse(File.read(options[:path], encoding: "UTF-8"))
abort("Unsupported dogfood corpus schema") unless document["schemaVersion"] == 1
cases = document["cases"]
abort("Dogfood corpus cases must be an array") unless cases.is_a?(Array)
abort("Dogfood corpus exceeds #{MAXIMUM_CASES} cases") if cases.length > MAXIMUM_CASES

ids = {}
required_keys = %w[id mode category utterance setup expectedStatus expectedResult checks]
cases.each_with_index do |entry, index|
  abort("Case #{index} must be an object") unless entry.is_a?(Hash)
  missing = required_keys.reject { |key| entry.key?(key) }
  abort("Case #{index} is missing: #{missing.join(', ')}") unless missing.empty?

  id = entry["id"]
  abort("Case #{index} has an invalid id") unless id.is_a?(String) && id.match?(/\A[a-z0-9-]+\z/)
  abort("Duplicate dogfood case id: #{id}") if ids[id]
  ids[id] = true

  abort("Case #{id} has an invalid mode") unless VALID_MODES.include?(entry["mode"])
  unless VALID_STATUSES.include?(entry["expectedStatus"])
    abort("Case #{id} has an invalid expectedStatus")
  end

  %w[category utterance setup expectedResult].each do |key|
    value = entry[key]
    unless value.is_a?(String) && !value.strip.empty? && value.bytesize <= MAXIMUM_TEXT_BYTES
      abort("Case #{id} has an invalid #{key}")
    end
  end

  checks = entry["checks"]
  unless checks.is_a?(Array) && !checks.empty? && checks.length <= 12 &&
      checks.all? { |check| check.is_a?(String) && !check.strip.empty? && check.bytesize <= 512 }
    abort("Case #{id} has invalid checks")
  end
end

puts "Dogfood corpus valid: #{cases.length} case(s)"
exit unless options[:list]

selected = cases.select do |entry|
  (!options[:mode] || entry["mode"] == options[:mode]) &&
    (!options[:category] || entry["category"] == options[:category])
end

selected.each_with_index do |entry, index|
  puts if index.positive?
  puts "[#{entry.fetch('mode')}] #{entry.fetch('id')}"
  puts "Say: #{entry.fetch('utterance')}"
  puts "Setup: #{entry.fetch('setup')}"
  puts "Expect: #{entry.fetch('expectedResult')}"
  entry.fetch("checks").each { |check| puts "  - #{check}" }
end
