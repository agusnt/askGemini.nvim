-- Title: askGimini
-- Description: A plugin to ask questions to Google's Gemini
-- Last change: 6-September-2024
-- Manteiner: Navarro-Torres, Agustin (https://github.com/agusnt)

local askGemini = {}

-- Load nui components
local Popup = require("nui.popup")
local Input = require("nui.input")
-- Global var
local Users_questions = {}

-- Show the Gemini response in a popup.
local function get_popup()
    local popup = Popup({
        position = "50%",
        size = { width = 100, height = "70%" },
        enter = true,
        focusable = false,
        border = { style = "rounded", text = {
                top = 'Asking Gemini', top_align = 'center'
            }
        },
    })

    -- Exit with ESC
    popup:map("n", "<Esc>", function()
        popup:unmount()
    end, { noremap = true })

    popup:mount()
    return popup
end

-- Sent a question to Gemini
local function lets_ask(question)
    if askGemini.api_key == '' then
        print('Please set the enviroment variable: GEMINI_API_KEY')
        return
    end
    local popup = get_popup()

    local function popup_txt(txt)
        -- Print line by line (Is there a better way to do it?)
        local dx = 0
        for s in txt:gmatch("[^\r\n]+") do
            if s == '' then s = ' ' end
            vim.api.nvim_buf_set_lines(popup.bufnr, dx, dx+1, false, {s} )
            vim.api.nvim_set_option_value('filetype', 'markdown', {buf = popup.bufnr})
            dx = dx + 1
        end
    end

    local json_question = {}
    json_question["contents"] = {}
    json_question["contents"][1] = {}
    json_question["contents"][1]["parts"] = {}
    json_question["contents"][1]["parts"][1] = {}
    json_question["contents"][1]["parts"][1]["text"] = question
    question = vim.fn.json_encode(json_question)
    -- Escape characters
    question = question:gsub("'", "'\\''")
    --question = question:gsub("@", "\\@")
    --question = question:gsub("$", "\\$")
    -- TODO: more models?
    local cmd = "curl -s " ..
        "-H 'Content-Type: application/json' " ..
        "-d '" .. question .. "' " ..
        "-X POST 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash-latest:generateContent?key="
        .. askGemini.api_key .. "'"
    local response = false
    -- Ask gemini and wait for a response
    vim.fn.jobstart(
        cmd, {
            stdout_buffered = true,
            stderr_buffered = true,
            on_stdout = function(_, data)
                if data then
                    response = true
                    local json_response = vim.fn.json_decode(data)
                    local res = json_response.candidates[1].content.parts[1].text
                    popup_txt(res)
                end
            end,
            on_stderr = function(_, data)
                if data and response == false then
                    local foo = 'There is an error: '
                    for _, v in ipairs(data) do foo = foo .. v end
                    popup_txt(foo)
                end
            end
        }
    )
end

-- Show an input so the user can ask Gemini
local function interactive_prompt(args)
    local input = Input({
        position = "50%",
        size = { width = 100 },
        border = {
            style = "single",
            text = { top = "[?]",},
        },
    }, {
        on_submit = function(value)
            if args ~= '' then
                value = value .. ': ' .. args
            end
            lets_ask(value)
        end
    })

    -- Exit with esc
    input:map("n", "<Esc>", function()
        input:unmount()
    end, { noremap = true })

    -- Show the menu
    input:mount()
end

-- Get the text selected by the user line by line
local function get_visual_selection_text(args)
    -- Get lines in visual
    local lstart = vim.fn.getpos("'<")[2]
    local lend = vim.fn.getpos("'>")[2]
    local lines = table.concat(vim.fn.getline(lstart,lend),'\n')

    if args['name'] ~= 'AskGeminiPrompt' then
        print(vim.inspect(Users_questions))
        print(Users_questions[args['name']])
        lets_ask(Users_questions[args['name']] .. ': ' .. lines)
    else
        interactive_prompt(lines)
    end

end

-- Setup function
function askGemini.setup(opts)
    -- Get API key from enviroment
    askGemini.api_key = os.getenv('GEMINI_API_KEY')

    -- Set special commands
    for dx, i in pairs(opts) do
        if dx == 'user_questions' then
            for _, j in pairs(i) do
                local cmd = 'AskGemini' .. j['cmd']
                vim.api.nvim_create_user_command(cmd, 
                    get_visual_selection_text, {range = true})
                Users_questions[cmd] = j['prompt']
            end
        end
    end

    vim.api.nvim_create_user_command('AskGemini', interactive_prompt, {})
    vim.api.nvim_create_user_command('AskGeminiPrompt', get_visual_selection_text, {range = true})
end

return askGemini
