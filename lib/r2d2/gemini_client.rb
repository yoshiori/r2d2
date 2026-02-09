require "gemini-ai"
require "rainbow"
require "logger"

require_relative "tools/read_file"
require_relative "tools/write_file"
require_relative "tools/exec_command"

class GeminiClient
  # https://gist.github.com/iinm/892b10427ca71bbd9f83707b9b95c181#file-agent-mjs-L20-L32
  PROMPT = "
  You are an interactive CLI agent specializing in software engineering tasks.

  # Core Behavior
  - Proactively use tools to gather information and solve problems.
  - Do not ask for confirmation at every step. Make decisions autonomously.
  - Use exec_command for shell operations (ls, find, grep, etc.) and read_file to inspect file contents.
  - Execute multiple tool calls in parallel when feasible.
  - Only ask questions when critical information is genuinely missing.

  # Tone
  - Be concise and direct. Avoid conversational filler.
  - Focus on action, not explanation.

  # Workflow for Tasks
  1. **Understand**: Use tools to explore the codebase and gather context.
  2. **Plan**: Form a brief plan internally.
  3. **Implement**: Execute using available tools.
  4. **Verify**: Confirm the result if applicable.

  # User Interactions
  - Respond in the same language the user uses.
  - File paths are relative to the current working directory.
  ".strip

  TOOLS = [
    ReadFile,
    WriteFile,
    ExecCommand
  ].freeze

  def initialize(api_key)
    @api_key = api_key
    @history = []
    @tools = TOOLS.to_h { |tool| [tool.name, tool.new] }
    @function_declarations = {
      function_declarations: TOOLS.map(&:definition)
    }
    @logger = Logger.new($stderr, level: ENV["R2D2_DEBUG"] ? Logger::DEBUG : Logger::INFO)
  end

  def chat(text, &block)
    @history << { role: "user", parts: { text: text } }
    generate(&block)
  end

  private

  def generate(&block)
    response = gemini.generate_content({
                                         contents: @history,
                                         tools: @function_declarations,
                                         system_instruction: { parts: { text: PROMPT } }
                                       })

    @logger.debug { JSON.pretty_generate(response) }

    candidates = response["candidates"]
    unless candidates
      @logger.error { "API error: No response received. Full response: #{response.inspect}" }
      yield "API error: No response received. "
      return
    end
    candidates.each do |candidate|
      parts = candidate.dig("content", "parts")
      unless parts
        reason = candidate["finishReason"]
        yield "Response blocked (#{reason})" if reason != "STOP"
        next
      end
      @history << { role: "model", parts: parts }
      process_parts(parts, &block)
    end
  rescue Faraday::TooManyRequestsError
    puts Rainbow("[Rate limit hit, retrying in 5s...]").faint
    sleep 5
    retry
  end

  def process_parts(parts, &block)
    function_response = []
    parts.each do |part|
      if part["functionCall"]
        function_response << execute_function(part["functionCall"])
      else
        yield part["text"]
      end
    end
    return if function_response.empty?

    @history << { role: "user", parts: function_response }
    generate(&block)
  end

  def execute_function(function_call)
    name = function_call["name"]
    args = function_call["args"]
    puts Rainbow("[#{name}] #{args}").faint
    begin
      result = @tools[name].execute(**args.transform_keys(&:to_sym))
    rescue StandardError => e
      result = "Error: #{e.message}"
    end
    @logger.debug { "Tool result: #{result}" }
    { functionResponse: { name: name, response: { result: result } } }
  end

  def gemini
    @gemini ||= Gemini.new(
      credentials: {
        service: "generative-language-api",
        api_key: @api_key,
        version: "v1beta"
      },
      options: { model: "gemini-2.0-flash" }
    )
  end
end
