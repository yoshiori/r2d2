require "openai"
require "rainbow"
require "logger"
require "json"

require_relative "tools/read_file"
require_relative "tools/write_file"
require_relative "tools/exec_command"

class LlmClient
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

  # File Editing Rules
  - IMPORTANT: Before modifying any existing file, ALWAYS read it first with read_file to get the current contents.
  - write_file overwrites the entire file. You must incorporate existing content when making partial changes.
  - Never guess or assume a file's contents. Always read first, then write.

  # Code Style
  - Before writing code, read related existing files to understand the project's naming conventions, style, and directory structure.
  - Follow the patterns already established in the codebase. Do not introduce new conventions without reason.

  # Workflow for Tasks
  1. **Understand**: First, grasp the project structure (e.g., `tree -L 2` or `ls`). Then read relevant files to gather context before making changes.
  2. **Plan**: Form a brief plan internally.
  3. **Implement**: Execute using available tools. Keep changes minimal and focused on what was requested.
  4. **Verify**: Run tests (exec_command), check for syntax errors, and read back modified files to confirm correctness.

  # Writing Tests (follow these steps in order)
  1. Read the source file of the class under test with read_file. Note the exact class name, module namespace, method names, parameters, and return values.
  2. Read existing test files to understand the project's test conventions (file location, require statements, style).
  3. Write the test using only the actual API you confirmed in step 1.
  4. Run the test and confirm it passes.
  - When writing tests, always mock or stub external dependencies (HTTP requests, API calls, database connections, etc.). Never let tests make real network requests.
  - NEVER guess class names, method names, or return values. If you didn't read it, you don't know it.

  # Error Recovery
  - When a tool call fails, read the error message carefully. The error often tells you exactly what is wrong (e.g., 'uninitialized constant Foo::Bar' means the class name Foo::Bar does not exist).
  - Try a different approach based on the error. Do not retry the same command. If unsure, use read_file to investigate.

  # Safety
  - Before running destructive operations (rm, git reset, overwriting critical files), confirm with the user.
  - Keep changes to the minimum required scope. Do not refactor or modify code unrelated to the task.

  # User Interactions
  - Respond in the same language the user uses.
  - File paths are relative to the current working directory.
  ".strip

  TOKEN_LIMIT = 100_000
  RECENT_KEEP_COUNT = 10

  TOOLS = [
    ReadFile,
    WriteFile,
    ExecCommand
  ].freeze

  def initialize(api_key)
    @api_key = api_key
    @history = []
    @tools = TOOLS.to_h { |tool| [tool.name, tool.new] }
    @tool_definitions = TOOLS.map(&:definition)
    @logger = Logger.new($stderr, level: ENV["R2D2_DEBUG"] ? Logger::DEBUG : Logger::INFO)
  end

  def chat(text, &block)
    @history << { "role" => "user", "content" => text }
    generate(&block)
  end

  private

  def generate(&block)
    response = client.chat(
      parameters: {
        model: "gemini-2.0-flash",
        messages: [{ "role" => "system", "content" => PROMPT }] + @history,
        tools: @tool_definitions
      }
    )
    @logger.debug { JSON.pretty_generate(response) }

    prompt_tokens = response.dig("usage", "prompt_tokens") || 0
    compress_history! if prompt_tokens > TOKEN_LIMIT

    message = response.dig("choices", 0, "message")
    unless message
      @logger.error { "API error: No response received. Full response: #{response.inspect}" }
      yield "API error: No response received."
      return
    end

    @history << message
    process_message(message, &block)
  rescue Faraday::TooManyRequestsError
    puts Rainbow("[Rate limit hit, retrying in 5s...]").faint
    sleep 5
    retry
  end

  def process_message(message, &block)
    if message["tool_calls"]
      tool_results = message["tool_calls"].map { |tool_call| execute_function(tool_call) }
      @history.concat(tool_results)
      generate(&block)
    elsif message["content"]
      yield message["content"]
    end
  end

  def execute_function(tool_call)
    name = tool_call.dig("function", "name")
    args = JSON.parse(tool_call.dig("function", "arguments"))
    puts Rainbow("[#{name}] #{args}").faint
    begin
      result = @tools[name].execute(**args.transform_keys(&:to_sym))
    rescue StandardError => e
      result = "Error: #{e.message}"
    end
    @logger.debug { "Tool result: #{result}" }
    { "role" => "tool", "tool_call_id" => tool_call["id"], "content" => result.to_s }
  end

  SUMMARIZE_PROMPT = <<~PROMPT
    Below is a conversation history between an AI assistant and a user.
    Please summarize this conversation concisely.

    Include:
    - What the user requested
    - What actions were taken (file paths, commands executed, etc.)
    - What the results were
    - Current state of the work

    Exclude:
    - Full file contents (paths are sufficient)
    - Full command output (just the key results)
  PROMPT

  def compress_history!
    split_at = find_safe_split_index
    return if split_at <= 0

    old_history = @history[0...split_at]
    recent_history = @history[split_at..]

    summary_response = client.chat(
      parameters: {
        model: "gemini-2.0-flash",
        messages: [{ "role" => "system", "content" => PROMPT }] +
                  old_history +
                  [{ "role" => "user", "content" => SUMMARIZE_PROMPT }]
      }
    )

    summary_text = summary_response.dig("choices", 0, "message", "content")

    @history = [
      { "role" => "user", "content" => "Summary of the conversation so far:\n#{summary_text}" },
      { "role" => "assistant", "content" => "Understood. Let's continue." }
    ] + recent_history

    puts Rainbow("History compressed: #{old_history.size} messages summarized").faint
  end

  def find_safe_split_index
    from = @history.size - RECENT_KEEP_COUNT

    index = @history[0...from].rindex do |msg|
      msg["role"] == "assistant" && !msg["tool_calls"]
    end

    index ? index + 1 : 0
  end

  def client
    @client ||= OpenAI::Client.new(
      access_token: @api_key,
      uri_base: "https://generativelanguage.googleapis.com/v1beta/openai/"
    )
  end
end
