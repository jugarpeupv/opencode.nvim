local config = require('opencode.config')

local M = {}

---@type boolean|'verbose'|nil
local cli_value
local cli_loaded = false

---@return boolean|'verbose'|nil
local function read_cli_turn_tokens()
  if cli_loaded then
    return cli_value
  end
  cli_loaded = true

  local xdg = vim.env.XDG_CONFIG_HOME
  local base = (xdg and xdg ~= '') and xdg or vim.fs.joinpath(vim.fn.expand('~'), '.config')
  local path = vim.fs.joinpath(base, 'opencode', 'cli.json')

  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or type(lines) ~= 'table' then
    return nil
  end

  local decoded_ok, decoded = pcall(vim.json.decode, table.concat(lines, '\n'))
  if not decoded_ok or type(decoded) ~= 'table' then
    return nil
  end

  local debug = decoded.debug
  if type(debug) ~= 'table' then
    return nil
  end

  local value = debug.turn_tokens
  if value == true or value == 'verbose' then
    cli_value = value
  end
  return cli_value
end

---@return boolean
function M.enabled()
  local setting = config.debug.turn_tokens
  if setting == 'auto' then
    setting = read_cli_turn_tokens() or false
  end
  return setting == true or setting == 'verbose'
end

function M.reset()
  cli_value = nil
  cli_loaded = false
end

---@param tokens table
---@return number
local function total_tokens(tokens)
  local cache = tokens.cache or {}
  return (tokens.input or 0) + (tokens.output or 0) + (tokens.reasoning or 0) + (cache.read or 0) + (cache.write or 0)
end

---@param tokens table
---@return OpencodeTurnTokensStep
local function step_usage(tokens)
  local cached = tokens.cache and tokens.cache.read or 0
  local total = total_tokens(tokens)
  return {
    new_tokens = total - cached,
    cached = cached,
    total = total,
  }
end

---@param entry table
---@return table[]
local function completed_token_usage(entry)
  local steps = {}
  for _, part in ipairs(entry.content or {}) do
    if part.kind == 'step_finish' and part.tokens then
      steps[#steps + 1] = part.tokens
    end
  end
  if #steps > 0 then
    return steps
  end

  -- V2 reports usage on the assistant step; only trust it once the step is done.
  if entry.tokens and (entry.finish ~= nil or (entry.time and entry.time.completed ~= nil)) then
    return { entry.tokens }
  end
  return {}
end

---Group completed assistant steps by user turn and attach the turn summary to the
---last step that reported usage.
---@param entries table[]
---@return table<string, OpencodeTurnTokensUsage>
function M.build(entries)
  ---@type table<string, OpencodeTurnTokensUsage>
  local result = {}
  ---@type { steps: OpencodeTurnTokensStep[], last_message_id: string|nil }
  local turn = { steps = {}, last_message_id = nil }

  local function close_turn()
    local message_id = turn.last_message_id
    if message_id and #turn.steps > 0 then
      local latest = turn.steps[#turn.steps]
      result[message_id] = {
        steps = #turn.steps,
        new_tokens = latest.new_tokens,
        cached = latest.cached,
        total = latest.total,
      }
    end
    turn = { steps = {}, last_message_id = nil }
  end

  for _, entry in ipairs(entries) do
    if entry.kind == 'user' then
      close_turn()
    elseif entry.kind == 'assistant' and entry.agent ~= 'compaction' then
      for _, tokens in ipairs(completed_token_usage(entry)) do
        local step = step_usage(tokens)
        if step.total > 0 then
          turn.steps[#turn.steps + 1] = step
          turn.last_message_id = entry.id
        end
      end
    end
  end
  close_turn()

  return result
end

---@param value number
---@return string
local function format_count(value)
  local text = tostring(math.max(0, math.floor(value)))
  local groups = 0
  repeat
    text, groups = text:gsub('^(%d+)(%d%d%d)', '%1,%2')
  until groups == 0
  return text
end

---@param usage OpencodeTurnTokensUsage
---@return string
function M.format(usage)
  local steps = usage.steps == 1 and '1 step' or string.format('%d steps', usage.steps)
  return string.format(
    'Tokens: %s · latest: %s new · %s cached · %s total',
    steps,
    format_count(usage.new_tokens),
    format_count(usage.cached),
    format_count(usage.total)
  )
end

return M
