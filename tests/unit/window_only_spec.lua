local window = require('opencode.commands.handlers.window')
local state = require('opencode.state')

describe('window only_opencode', function()
  it('keeps input/output and floats while closing other splits', function()
    local original_windows = state.store.get('windows')
    local original_last = state.store.get('last_code_win_before_opencode')
    local original_buf = vim.api.nvim_get_current_buf()

    vim.cmd('tabnew')
    local base_win = vim.api.nvim_get_current_win()

    local output_buf = vim.api.nvim_create_buf(false, true)
    local input_buf = vim.api.nvim_create_buf(false, true)
    local float_buf = vim.api.nvim_create_buf(false, true)

    vim.cmd('split')
    local output_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(output_win, output_buf)

    vim.cmd('split')
    local input_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(input_win, input_buf)

    local float_win = vim.api.nvim_open_win(float_buf, false, {
      relative = 'editor',
      width = 10,
      height = 2,
      row = 1,
      col = 1,
    })

    state.store.set_raw('windows', {
      output_win = output_win,
      output_buf = output_buf,
      input_win = input_win,
      input_buf = input_buf,
    })

    window.actions.only_opencode()

    assert.is_true(vim.api.nvim_win_is_valid(output_win))
    assert.is_true(vim.api.nvim_win_is_valid(input_win))
    assert.is_true(vim.api.nvim_win_is_valid(float_win))
    assert.is_false(vim.api.nvim_win_is_valid(base_win))

    state.store.set_raw('windows', original_windows)
    state.ui.set_last_code_window(original_last)
    pcall(vim.api.nvim_win_close, float_win, true)
    vim.cmd('tabclose')
    pcall(vim.api.nvim_buf_delete, output_buf, { force = true })
    pcall(vim.api.nvim_buf_delete, input_buf, { force = true })
    pcall(vim.api.nvim_buf_delete, float_buf, { force = true })
    pcall(vim.api.nvim_set_current_buf, original_buf)
  end)

  it('restores the last code buffer and default width after only_opencode', function()
    local ui = require('opencode.ui.ui')
    local original_windows = state.store.get('windows')
    local original_last = state.store.get('last_code_win_before_opencode')
    local original_code_buf = state.store.get('current_code_buf')
    local original_ratio = state.store.get('last_window_width_ratio')
    local original_zoom = state.store.get('pre_zoom_width')

    vim.cmd('tabnew')
    local code_buf = vim.api.nvim_get_current_buf()
    local output_buf = vim.api.nvim_create_buf(false, true)
    local input_buf = vim.api.nvim_create_buf(false, true)

    vim.cmd('split')
    local output_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(output_win, output_buf)

    vim.cmd('split')
    local input_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(input_win, input_buf)

    state.store.set_raw('windows', {
      output_win = output_win,
      output_buf = output_buf,
      input_win = input_win,
      input_buf = input_buf,
      position = 'right',
    })
    state.ui.set_current_code_buf(code_buf)

    window.actions.only_opencode()
    state.ui.set_last_window_width_ratio(0.95)
    state.ui.set_pre_zoom_width(60)

    ui.hide_visible_windows(state.windows, true)

    assert.is_nil(state.last_window_width_ratio)
    assert.is_nil(state.pre_zoom_width)
    assert.equals(code_buf, vim.api.nvim_get_current_buf())

    state.store.set_raw('windows', original_windows)
    state.ui.set_last_code_window(original_last)
    state.ui.set_current_code_buf(original_code_buf)
    state.ui.set_last_window_width_ratio(original_ratio)
    state.ui.set_pre_zoom_width(original_zoom)
    state.ui.clear_hidden_window_state()
    vim.cmd('tabclose')
    pcall(vim.api.nvim_buf_delete, output_buf, { force = true })
    pcall(vim.api.nvim_buf_delete, input_buf, { force = true })
  end)
end)
