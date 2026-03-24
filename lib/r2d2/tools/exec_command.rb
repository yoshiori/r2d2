require "open3"

class ExecCommand
  def self.name
    "exec_command"
  end

  def self.description
    "Execute a shell command and return its output. " \
    "Supports any UNIX command (ls, grep, find, cat, curl, etc.)."
  end

  def self.parameters
    {
      type: "object",
      properties: {
        command: {
          type: "string",
          description: "The command to execute"
        },
        args: {
          type: "array",
          description: "Array of arguments for the command",
          items: {
            type: "string"
          }
        }
      },
      required: ["command"]
    }
  end

  def self.definition
    { type: "function", function: { name: name, description: description, parameters: parameters } }
  end

  def execute(command:, args: [])
    output, status = Open3.capture2e(command, *args)
    "exit_code: #{status.exitstatus}\n#{output}"
  end
end
