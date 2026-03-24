# R2D2

A simple AI agent built with Ruby, created for learning purposes. It works with any OpenAI-compatible API (Gemini, Ollama, etc.).

## Overview

R2D2 is a CLI-based AI agent that can interact with users and perform software engineering tasks using Function Calling.

## Setup

```bash
git clone https://github.com/yoshiori/r2d2.git
cd r2d2
bin/setup
```

Create a `.env` file to configure your LLM backend:

```
LLM_API_KEY=your_api_key_here
LLM_API_BASE=https://generativelanguage.googleapis.com/v1beta/openai/
LLM_MODEL=gemini-2.0-flash
```

### Examples

**Gemini:**
```
LLM_API_KEY=your_gemini_api_key
LLM_API_BASE=https://generativelanguage.googleapis.com/v1beta/openai/
LLM_MODEL=gemini-2.0-flash
```

**Ollama (local):**
```
LLM_API_KEY=ollama
LLM_API_BASE=http://localhost:11434/v1/
LLM_MODEL=llama3.1:8b
```

## Usage

```bash
bundle exec ruby bin/r2d2
```

Type `exit` to quit.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
