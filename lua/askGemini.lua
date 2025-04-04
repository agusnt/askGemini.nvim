-- Title: askGimini
-- Description: A plugin to ask questions to Google's Gemini
-- Last change: 1-April-2025 -- Using current date as requested
-- Manteiner: Navarro-Torres, Agustin (https://github.com/agusnt)

-- Use local variables for better scoping
local Popup = require("nui.popup")
local Input = require("nui.input")

-- Define the main plugin table
local askGemini = {}

-- Default configuration (can be overridden in setup)
askGemini.config = {
    model = "gemini-1.5-flash-latest", -- Updated default model
    default_prompt_for_selection = "Explain the following code:", -- Default prompt for AskGeminiPrompt
    api_key = nil -- Will be populated from environment or setup
}

-- =============================================================================
-- Helper Functions for UI
-- =============================================================================

-- Show the Gemini response in a popup.
local function get_popup()
    local popup = Popup({
        position = "50%",
        size = { width = "80%", height = "70%" }, -- Adjusted size
        enter = true,
        focusable = true, -- Allow focusing to scroll, copy, etc.
        zindex = 50,
        border = {
            style = "rounded",
            text = { top = ' Gemini Response ', top_align = 'center' }
        },
        win_options = {
            wrap = true,
            linebreak = true,
            conceallevel = 0,
            concealcursor = "", -- Don't conceal in popup
        },
    })

    -- Mappings for the popup window
    popup:map("n", "<Esc>", function() popup:unmount() end, { noremap = true, silent = true })
    popup:map("n", "q", function() popup:unmount() end, { noremap = true, silent = true })
    -- Add more mappings if needed (e.g., scrolling)

    popup:mount()
    return popup
end

-- Helper function to safely set lines in the popup buffer
local function set_popup_lines(popup_buffer, text_content)
    -- Ensure buffer is valid
    if not vim.api.nvim_buf_is_valid(popup_buffer) then
        vim.notify("Popup buffer is invalid.", vim.log.levels.ERROR)
        return
    end

    -- Clear existing content
    vim.api.nvim_buf_set_lines(popup_buffer, 0, -1, false, {})

    -- Split content into lines (handle different line endings)
    local lines = vim.split(text_content, "\n")

    -- Set new lines
    vim.api.nvim_buf_set_lines(popup_buffer, 0, -1, false, lines)

    -- Set filetype for potential syntax highlighting
    vim.api.nvim_buf_set_option(popup_buffer, 'filetype', 'markdown')
    -- Ensure buffer is not modifiable by user typing
    vim.api.nvim_buf_set_option(popup_buffer, 'modifiable', false)
end


-- =============================================================================
-- Core API Interaction Function
-- =============================================================================

-- Sent a question to Gemini
local function lets_ask(question_text)
    -- Check API key existence early
    if not askGemini.config.api_key or askGemini.config.api_key == '' then
        vim.notify('GEMINI_API_KEY is not set. Please set the environment variable or pass it in setup.', vim.log.levels.ERROR)
        return
    end

    local popup = get_popup()
    -- Set initial loading message
    set_popup_lines(popup.bufnr, "Asking Gemini...")

    -- Construct JSON payload
    -- Note: Simpler structure might work depending on API version (e.g., just "prompt": question_text)
    -- Using the more standard structure for robustness
    local json_payload = {
        contents = {
            {
                parts = {
                    { text = question_text }
                }
            }
        }
        -- Add generationConfig here if needed (temperature, max tokens etc.)
        -- generationConfig = { ... }
    }

    -- Encode JSON safely
    local ok, json_body = pcall(vim.json.encode, json_payload)
    if not ok then
        set_popup_lines(popup.bufnr, "Error encoding JSON request: " .. tostring(json_body))
        return
    end

    -- Escape single quotes for the shell command (-d '...')
    -- WARNING: This is basic escaping and might not be fully secure if complex text is involved.
    -- Consider using libraries or more robust escaping if needed.
    local escaped_json_body = string.gsub(json_body, "'", "'\\''")

    -- Construct the API URL using the configured model
    local api_url = string.format(
        "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s",
        askGemini.config.model,  -- Use the configured model
        askGemini.config.api_key
    )

    -- Construct the curl command
    local cmd = {
        "curl", "-s", "-X", "POST",
        "-H", "Content-Type: application/json",
        "-d", escaped_json_body, -- Use the properly escaped JSON body
        api_url
    }

    -- Variable to track if stdout callback was successful
    local response_received = false

    -- Run the job asynchronously
    vim.fn.jobstart(cmd, {
        stdout_buffered = true,
        stderr_buffered = true,
        on_stdout = function(_, data, _)
            if data and #data > 0 then -- Check if data is not nil and not empty table
                local full_response = table.concat(data, "\n")
                -- Attempt to decode JSON response
                local decode_ok, json_response = pcall(vim.json.decode, full_response)
                if decode_ok and json_response then
                    -- Extract text safely using pcall or checks
                    local extract_ok, result_text = pcall(function()
                        -- Adjust path based on actual API response structure
                        return json_response.candidates[1].content.parts[1].text
                    end)

                    if extract_ok and result_text then
                        set_popup_lines(popup.bufnr, result_text)
                        response_received = true -- Mark success
                    else
                        -- Handle cases where the expected structure isn't found
                        set_popup_lines(popup.bufnr, "Error: Could not extract text from Gemini response.\n\nRaw Response:\n" .. full_response)
                    end
                elseif json_response and json_response.error then
                     -- Handle API error message if present in JSON
                    local error_msg = json_response.error.message or "Unknown API error"
                    set_popup_lines(popup.bufnr, "API Error: " .. error_msg .. "\n\nRaw Response:\n" .. full_response)
                else
                    -- Handle non-JSON or malformed JSON response
                    set_popup_lines(popup.bufnr, "Error: Received non-JSON or malformed response from API.\n\nRaw Response:\n" .. full_response)
                end
            end
        end,
        on_stderr = function(_, data, _)
            -- Only show stderr if stdout didn't process successfully
            if not response_received and data and #data > 0 then
                local error_output = table.concat(data, "\n")
                set_popup_lines(popup.bufnr, "Error during API call (stderr):\n" .. error_output)
            end
        end,
        on_exit = function(_, code, _)
            -- Optional: Notify on non-zero exit code if no other error was shown
            if not response_received and code ~= 0 then
                 if vim.api.nvim_buf_is_valid(popup.bufnr) then
                    -- Append exit code info if popup still exists and no specific error shown yet
                    local current_content = table.concat(vim.api.nvim_buf_get_lines(popup.bufnr, 0, -1, false), "\n")
                    if not string.find(current_content, "Error:") and not string.find(current_content, "API Error:") then
                         set_popup_lines(popup.bufnr, current_content .. "\n\nAPI call process exited with code: " .. code)
                    end
                 else
                    vim.notify("API call process exited with code: " .. code, vim.log.levels.WARN)
                 end
            end
            -- Ensure focus returns to the original window after job completion
            vim.cmd('stopinsert') -- Exit insert mode if any
        end
    })
end

-- =============================================================================
-- Command Handlers
-- =============================================================================

-- Show an input so the user can ask Gemini interactively
local function interactive_prompt()
    local input = Input({
        position = "50%",
        size = { width = "70%" }, -- Adjusted size
        border = {
            style = "rounded",
            text = { top = " Ask Gemini ", top_align = "center" },
        },
        title = "Enter your question:",
        prompt = "> ",
    }, {
        on_submit = function(value)
            if value and value ~= "" then -- Check if input is not empty
                lets_ask(value)
            end
        end
    })

    -- Mappings for the input window
    input:map("i", "<Esc>", function() input:unmount() end, { noremap = true, silent = true })
    input:map("n", "<Esc>", function() input:unmount() end, { noremap = true, silent = true })
    input:map("n", "q", function() input:unmount() end, { noremap = true, silent = true })


    -- Show the input prompt
    input:mount()
    -- Enter insert mode automatically
    vim.cmd('startinsert')
end

-- Get the text selected by the user (visual mode) and ask Gemini
-- This function is called by the closures created in setup
local function ask_with_visual_selection(prompt, handler_opts)
    -- Get lines from the range provided by the command handler_opts
    local start_line = handler_opts.line1
    local end_line = handler_opts.line2
    -- Get lines from the current buffer (0)
    local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
    local selected_text = table.concat(lines, '\n')

    if selected_text == "" then
        vim.notify("No text selected.", vim.log.levels.WARN)
        return
    end

    -- Combine the specific prompt with the selected text
    local full_question = prompt .. "\n\n```\n" .. selected_text .. "\n```" -- Add markdown backticks for clarity

    -- Call the core function
    lets_ask(full_question)
end


-- =============================================================================
-- Setup Function
-- =============================================================================

-- Setup function
function askGemini.setup(opts)
    opts = opts or {} -- Ensure opts is a table

    -- Get API key from environment (can be overridden by opts.api_key)
    askGemini.config.api_key = os.getenv('GEMINI_API_KEY')
    if opts.api_key then
      askGemini.config.api_key = opts.api_key -- Allow overriding via setup opts
      vim.notify("Using Gemini API key from setup options.", vim.log.levels.INFO)
    end

    -- Check if API key is finally set
    if not askGemini.config.api_key or askGemini.config.api_key == '' then
        vim.notify('GEMINI_API_KEY is not set. Set environment variable or pass api_key in setup.', vim.log.levels.WARN)
        -- Don't return here, allow plugin to load but commands will fail until key is set
    end

    -- Set model, allowing override from opts
    if opts.model then
        askGemini.config.model = opts.model
    end
    -- Update default prompt if provided
    if opts.default_prompt_for_selection then
        askGemini.config.default_prompt_for_selection = opts.default_prompt_for_selection
    end


    -- Process user-defined questions/commands using closures
    if opts.user_questions then
        -- Use ipairs for iterating lists/arrays
        for _, question_config in ipairs(opts.user_questions) do
            -- Validate config item structure
            if type(question_config) == "table" and question_config.cmd and question_config.prompt then
                local cmd_name = 'AskGemini' .. question_config.cmd
                local prompt_text = question_config.prompt -- Capture the prompt specific to this command

                -- Create a closure function as the command handler.
                -- This function captures the 'prompt_text' for this specific command.
                local command_handler = function(handler_opts)
                    -- handler_opts contains range info like { line1, line2 }
                    -- Call the unified function with the captured prompt and range info
                    ask_with_visual_selection(prompt_text, handler_opts)
                end

                vim.api.nvim_create_user_command(
                    cmd_name,
                    command_handler,
                    {
                        range = true, -- Command works on a range (visual selection)
                        nargs = '0',  -- Command takes no arguments itself
                        desc = "Ask Gemini: " .. prompt_text -- Description for command listings
                    }
                )
            else
                vim.notify("Invalid item format in 'user_questions'. Expected {cmd = '...', prompt = '...'}.", vim.log.levels.WARN)
            end
        end
    end

    -- Create the standard interactive command
    vim.api.nvim_create_user_command(
        'AskGemini',
        interactive_prompt, -- Directly call the interactive prompt function
        {
            nargs = '0', -- Takes no arguments
            desc = "Ask Gemini interactively"
        }
    )

    -- Create the command for asking about visual selection with a default prompt
    local default_prompt = askGemini.config.default_prompt_for_selection -- Capture default prompt
    vim.api.nvim_create_user_command(
        'AskGeminiPrompt',
        function(handler_opts) -- Closure capturing the default prompt
            ask_with_visual_selection(default_prompt, handler_opts)
        end,
        {
            range = true,
            nargs = '0',
            desc = "Ask Gemini about selection (" .. default_prompt .. ")" -- Dynamic description
        }
    )

    vim.notify("askGemini setup complete. Model: " .. askGemini.config.model, vim.log.levels.INFO)
end

-- Return the plugin table so it can be required
return askGemini
