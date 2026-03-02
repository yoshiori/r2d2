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
