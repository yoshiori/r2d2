class WriteFile
  def self.name
    "write_file"
  end

  def self.description
    "Write content to a file. If the file already exists, it will be overwritten."
  end

  def self.parameters
    {
      type: "object",
      properties: {
        path: {
          type: "string",
          description: "The relative file path from the current working directory"
        },
        content: {
          type: "string",
          description: "The content to write to the file"
        }
      },
      required: %w[path content]
    }
  end

  def self.definition
    { type: "function", function: { name: name, description: description, parameters: parameters } }
  end

  def execute(path:, content:)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    "Successfully wrote to #{path}"
  end
end
