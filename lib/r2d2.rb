# frozen_string_literal: true

require "gemini-ai"
require "rainbow"
require "reline"

require_relative "r2d2/version"
require_relative "r2d2/gemini_client"

module R2d2
  class Error < StandardError; end

  PREFIX = Rainbow("● ").cyan
  INDENT = "  " # Since it contains control characters, PREFIX.length is not used.

  def self.start(_args)
    client = GeminiClient.new(ENV["GEMINI_API_KEY"])
    puts Rainbow("R2D2 is starting...").bright.cyan
    loop do
      puts ""
      input = Reline.readline(Rainbow("❯ ").bright.cyan.to_s, true)
      break if input.nil? || input.downcase == "exit"

      client.chat(input) do |message|
        R2d2.print_response(message)
      end
    end
    puts Rainbow("bye!").bright.cyan
  end

  def self.print_response(message)
    lines = message.lines
    puts ""
    puts "#{PREFIX}#{lines.first}"
    puts lines.drop(1).map { |line| "#{INDENT}#{line}" }.join unless lines.size <= 1
    puts ""
  end
end
