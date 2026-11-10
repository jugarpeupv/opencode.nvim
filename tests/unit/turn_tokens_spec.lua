local assert = require('luassert')
local config = require('opencode.config')
local turn_tokens = require('opencode.ui.turn_tokens')

describe('turn token usage', function()
  local original_setting

  local function tokens(input, output, reasoning, read, write)
    return {
      input = input,
      output = output,
      reasoning = reasoning,
      cache = { read = read, write = write },
    }
  end

  local function user(id)
    return { id = id, kind = 'user', content = {} }
  end

  local function assistant(id, token_usage, fields)
    return vim.tbl_extend('force', {
      id = id,
      kind = 'assistant',
      finish = 'stop',
      time = { created = 1, completed = 2 },
      content = {},
      tokens = token_usage,
    }, fields or {})
  end

  before_each(function()
    original_setting = config.debug.turn_tokens
  end)

  after_each(function()
    config.debug.turn_tokens = original_setting
    turn_tokens.reset()
  end)

  it('groups completed steps by user turn and reports the latest step', function()
    local usage = turn_tokens.build({
      user('u1'),
      assistant('a1', tokens(100, 20, 0, 10, 5)),
      assistant('a2', tokens(200, 30, 0, 50, 5)),
      user('u2'),
      assistant('a3', tokens(300, 40, 0, 100, 0)),
    })

    assert.same({ steps = 2, new_tokens = 235, cached = 50, total = 285 }, usage.a2)
    assert.same({ steps = 1, new_tokens = 340, cached = 100, total = 440 }, usage.a3)
    assert.is_nil(usage.a1)
  end)

  it('ignores incomplete steps and compaction summaries', function()
    local incomplete = assistant('a1', tokens(100, 0, 0, 0, 0), { time = { created = 1 } })
    incomplete.finish = nil
    local usage = turn_tokens.build({
      user('u1'),
      incomplete,
      assistant('a2', tokens(200, 0, 0, 0, 0), { agent = 'compaction' }),
      assistant('a3', tokens(300, 0, 0, 0, 0)),
    })

    assert.is_nil(usage.a1)
    assert.is_nil(usage.a2)
    assert.same({ steps = 1, new_tokens = 300, cached = 0, total = 300 }, usage.a3)
  end)

  it('counts V1 step-finish parts', function()
    local usage = turn_tokens.build({
      user('u1'),
      assistant('a1', nil, {
        content = {
          { kind = 'step_finish', tokens = tokens(10, 0, 0, 0, 0) },
          { kind = 'step_finish', tokens = tokens(20, 0, 0, 5, 0) },
        },
      }),
    })

    assert.same({ steps = 2, new_tokens = 20, cached = 5, total = 25 }, usage.a1)
  end)

  it('formats the summary line like the OpenCode TUI', function()
    assert.equals(
      'Tokens: 2 steps · latest: 7,973 new · 5,888 cached · 13,861 total',
      turn_tokens.format({ steps = 2, new_tokens = 7973, cached = 5888, total = 13861 })
    )
    assert.equals(
      'Tokens: 1 step · latest: 1 new · 0 cached · 1 total',
      turn_tokens.format({ steps = 1, new_tokens = 1, cached = 0, total = 1 })
    )
  end)

  it('enables rendering only for true or verbose settings', function()
    config.debug.turn_tokens = true
    assert.is_true(turn_tokens.enabled())

    config.debug.turn_tokens = 'verbose'
    assert.is_true(turn_tokens.enabled())

    config.debug.turn_tokens = false
    assert.is_false(turn_tokens.enabled())
  end)
end)
