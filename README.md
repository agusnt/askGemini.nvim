# askGemini.nvim

A plugin to ask questions to Google's gemini from Neovim. 

The purpose of this plugin is having an interface to communicate with Gemini API,
this way you don't have to move to your browers.

<img src="https://github.com/agusnt/askGemini.nvim/blob/main/img/Input.png?raw=true" width="100">

<img src="https://github.com/agusnt/askGemini.nvim/blob/main/img/Answer.png?raw=true" width="100">

## Installation

### Pre-requisites

1. Make sure you have `curl` installed.
2. Get a [Gemini's API key from Google](https://ai.google.dev/gemini-api/docs/api-key).
3. Set the GEMINI_API_KEY environment variable: `export GEMINI_API_KEY=<your api key>`. 

### Lazy

You can install askGemini with [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    'agusnt/askGemini.nvim',
    dependencies = { 'MunifTanjim/nui.nvim' }
}
```

## Usage

The plugin expose the following two commands:

### `AskGemini`

Open a prompt to ask anything you want to gemini.

### `AskGeminiPrompt`

Open a prompt to ask anything you want to Gemini. Gemini will then respond with 
the line your cursor is currently on in Vim (or the selected line in normal mode).

## Configuration

If you use **a lot** of prompts from `:AskGeminiPrompt`, you can create your own 
command to save yourself the extra time of writing the prompt. Just add the 
following when configuring the plugin: 

```lua
require('askGemini').setup({
      user_questions = {
          {
              -- The command AskGeminiGrammar will check grammar and spelling 
              cmd = 'Grammar',
              prompt = 'Check grammar and spelling'
          },
          {
              -- The command AskGeminiGrammar will explain the selected ExplainCode
              -- to you
              cmd = 'ExplainCode',
              prompt = 'What this code does?'
          }
      }
})
```

The `cmd` field is the name of the command (with `AskGemini` prepended; 
e.g., if `cmd` is *Grammar*, the final command will be `:AskGeminiGrammar`). 
The `prompt` field contains the prompt that will be sent to Gemini. 

## Why a new AI-powered plugin?

The alternatives are great, but they offer too many options, and most focus on 
coding with AI. I want something simpler that I can extend with only the three 
options I use from Gemini. 

## Similar plugins

* [ChatGPT.nvim](https://github.com/jackMort/ChatGPT.nvim)
* [codecompanion.nvim](https://github.com/olimorris/codecompanion.nvim)
