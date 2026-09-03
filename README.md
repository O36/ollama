# ollama

Local Ollama stack with Open WebUI and SearXNG. Designed for use with opencode.  
  
## Directory Structure  
  
```
ollama/
├── data/
│   ├── models/       # Ollama model storage (blobs, manifests, keys)
│   ├── openwebui/    # User accounts, chat history
│   ├── prompts/      # System prompt files
│   └── searxng/      # SearXNG configuration
├── logs/             # Application logs
├── scripts/
│   ├── coldstart.sh  # Bring up all containers from scratch
│   ├── stop.sh       # Stop container, optionally remove them
│   └── prompts.sh    # Prompt management
├── secrets           # Environment variables (git-ignored)
├── secrets.template  # Template - copy to secrets and fill in
├── README.md
└── LICENSE
```
  
## Prerequisites  
  
- Podman (or Docker with podman alias)  
- Internet connection (for pulling images)  
  
## Setup  
  
1. Copy the secrets.example file to secrets in the project root and fill in the values:  
  
```bash
cp secrets.template secrets
```
  
2. Run the cold-start script:  
  
```bash
./scripts/coldstart.sh
```
  
This creates the 'ollama-net' podman network, starts all three containers, and prompts you to pull a model.  
  
## Stopping / Rebuilding
  
```bash
./scripts/stop.sh
```
  
Stops all containers. You'll be asked whether to remove them as well.  
Removal is safe: models, chat history, and web-search config all live under 'data/', outside of the containers, so another './scripts/coldstart.sh' rebuilds the stack with everything intact.  
  
## Services  
  
| Service | Container | Port | Purpose |  
|---------|-----------|------|---------|  
| Ollama | ollama | 11434 | LLM inference API |  
| Open WebUI | openwebui | 3000 | Browser-based chat interface |  
| SearXNG | searxng | 8888 | Web search for RAG |  
  
## Model Selection  
  
The cold-start script first shows models already installed, then presents an interactive menu:  
  
| # | Model | Type | Params | RAM | Context |  
|---|-------|------|--------|-----|---------|  
| 1 | llama3.1:8b | general-purpose | 8B | ~6 GB | 128k |  
| 2 | llama3.1:70b | general-purpose | 70B | ~40 GB | 128k |  
| 3 | mistral | fast, efficient | 7B | ~4 GB | 32k |  
| 4 | phi3 | compact | 3.8B | ~2 GB | 128k |  
| 5 | gemma2 | balanced | 9B | ~5 GB | 8k |  
| 6 | codellama | code-focused | 7B | ~4 GB | 16k |  
| 7 | deepseek-coder | code-focused | 6.7B | ~4 GB | 16k |  
| 8 | qwen2.5 | strong reasoning | 7B | ~5 GB | 128k |  
| 9 | qwen2.5:32b | strong reasoning | 32B | ~20 GB | 128k |  
| 10 | custom | any model from ollama.com/library | - | - | - |  
  
## Usage with opencode  
  
Configure opencode to use the local Ollama instance. The API key is stored in your `secrets` file:  
  
```json  
{
  "provider": {
    "ollama": {
      "apiKey": "${OPENCODE_OLLAMA_API_KEY}",
      "models": {
        "llama3.1:8b": {
          "maxTokens": 8192,
          "contextWindow": 128000
        }
      }
    }
  }
}
```
  
## Web Search (RAG)  
  
Open WebUI is pre-configured to use SearXNG for web search. To confirm:  
  
1. Open Open WebUI at `http://localhost:3000`
2. Go to **Admin Panel** → **Settings** → **Web Search**
3. Confirm **Enable Web Search** is on and engine is set to 'searxng'
4. Confirm **Searxng Query URL** to `http://searxng:8080/search?q=<query>`  
  
## System Prompts  
  
System prompts are stored in `data/prompts/` as Markdown files with YAML frontmatter. Use the management script to work with them:  
  
```bash
# List all prompts
./scripts/prompts.sh list

# Display a prompt (copy/paste into Open WebUI)
./scripts/prompts.sh show code-assistant

# Create a new prompt interactively
./scripts/prompts.sh create

# Delete a prompt
./scripts/prompts.sh delete creative-writer
```
  
### Using prompts in Open WebUI  
  
1. Run `./scripts/prompts.sh show <name>` to display the prompt  
2. Copy the output  
3. Open Open WebUI → **Admin Panel** → **Settings** → **System Prompt**  
4. Paste and save  
  
### Prompt file format  
  
```markdown
---
name: Code Assistant
description: Specialized in code review and refactoring
tags: [code, programming]
---

You are a senior software engineer...
```
  
The YAML frontmatter (`name`, `description`, `tags`) is used for display purposes only. The actual system prompt is everything after the closing `---`.  
  
### Included prompts  
  
| File | Name | Purpose |  
|------|------|---------|  
| `code-assistant.md` | Code Assistant | Code review, refactoring, best practices |  
| `creative-writer.md` | Creative Writer | Storytelling, content creation |  
| `technical-docs.md` | Technical Writer | Documentation, guides, explanations |  
  
## Logs  
  
Application logs are stored in `logs/ollama.log`.  

## License  

MIT - see [LICENSE](LICENSE).  
  
