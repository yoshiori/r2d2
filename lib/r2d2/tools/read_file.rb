class ReadFile
  def self.name
    "read_file"
  end

  def self.description
    "Read the contents of a file at the given path. " \
    "Use this to understand code, gather context, or inspect files " \
    "before answering questions or making decisions."
  end

  def self.parameters
    {
      type: "object",
      properties: {
        path: {
          type: "string",
          description: "The relative file path from the current working directory"
        }
      },
      required: ["path"]
    }
  end

  def self.definition
    { type: "function", function: { name: name, description: description, parameters: parameters } }
  end

  def execute(path:)
    File.read(path)
  end
end
