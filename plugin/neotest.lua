local notify = vim.notify
local levels = vim.log.levels
local neotest = require("neotest")
local api = vim.api

local cmd_completion_store = {
  [""] = {
    "attach",
    "jump",
    "output",
    "output-panel",
    "run",
    "stop",
    "summary",
  },
  jump = {
    "next",
    "prev",
  },
  ["output-panel"] = {
    "open",
    "close",
    "toggle",
    "clear",
  },
  run = {
    "file",
    "last",
  },
  summary = {
    "close",
    "mark",
    "open",
    "toggle",
  },
  ["summary:mark"] = {
    "clear",
    "run",
    "toggle",
  },
}

local opt_completion_store = {
  adapter = function(arg)
    local part = arg:gsub("^adapter=", "")
    return vim.tbl_filter(function(cmd)
      return not not string.find(cmd, "^" .. part)
    end, neotest.state.adapter_ids())
  end,
  strategy = function(arg)
    local part = arg:gsub("^strategy=", "")
    return vim.tbl_filter(function(cmd)
      return not not string.find(cmd, "^" .. part)
    end, { "integrated", "dap" })
  end,
}

local commands
commands = {
  attach = function(params)
    neotest.run.attach(params.opts)
  end,
  jump = {
    next = function(params)
      neotest.jump.next(params.opts)
    end,
    prev = function(params)
      neotest.jump.prev(params.opts)
    end,
  },
  output = function(params)
    neotest.output.open(params.opts)
  end,
  ["output-panel"] = {
    function()
      commands["output-panel"].toggle()
    end,
    close = function()
      neotest.output_panel.close()
    end,
    open = function()
      neotest.output_panel.open()
    end,
    toggle = function()
      neotest.output_panel.toggle()
    end,
    clear = function()
      require("neotest").output_panel.clear()
    end,
  },
  run = {
    function(params)
      neotest.run.run(params.opts)
    end,
    file = function(params)
      params.opts[1] = vim.fn.expand("%")
      commands.run[1](params.opts)
    end,
    last = function(params)
      neotest.run.run_last(params.opts)
    end,
  },
  stop = function(params)
    neotest.run.stop(params.opts)
  end,
  summary = {
    function()
      commands.summary.toggle()
    end,
    close = function()
      neotest.summary.close()
    end,
    mark = {
      function()
        commands.summary.mark.toggle()
      end,
      clear = function(params)
        neotest.summary.clear_marked(params.opts)
      end,
      run = function(params)
        neotest.summary.run_marked(params.opts)
      end,
      toggle = function()
        local key = require("neotest.config").summary.mappings.mark
        if type(key) == "table" then
          key = key[1]
        end
        api.nvim_feedkeys(api.nvim_replace_termcodes(key, true, false, true), "m", false)
      end,
    },
    open = function()
      neotest.summary.open()
    end,
    toggle = function()
      neotest.summary.toggle()
    end,
  },
}

local function eval_luastring(value)
  local evaluated = loadstring("return " .. value, value)()
  if evaluated == nil then
    -- Treat as unquoted string
    evaluated = value
  end
  return evaluated
end

local function make_params(info, args)
  local params = {
    bang = info.bang,
    opts = {},
  }

  for _, arg in ipairs(args) do
    if arg:find("=", 1) then
      local parts = vim.split(arg, "=")
      local key = table.remove(parts, 1)
      local value = table.concat(parts, "=")
      params.opts[key] = eval_luastring(value)
    else
      table.insert(params.opts, eval_luastring(arg))
    end
  end

  return params
end

api.nvim_create_user_command("Neotest", function(info)
  local args = info.fargs

  ---@type string|nil
  local cmd_name = table.remove(args, 1)
  if not cmd_name then
    return notify("[Neotest] missing command", levels.WARN)
  end

  local cmd = commands[cmd_name]
  if type(cmd) == "function" then
    return cmd(make_params(info, args))
  end

  if type(cmd) ~= "table" then
    return notify(("[Neotest] unknown command: %s"):format(cmd_name), levels.WARN)
  end

  if cmd[args[1]] then
    local subcmd_name = table.remove(args, 1)
    local subcmd = cmd[subcmd_name]

    if type(subcmd) == "function" then
      return subcmd(make_params(info, args))
    end

    if type(subcmd) ~= "table" then
      return notify(("[Neotest] unknown subcommand: %s"):format(subcmd_name), levels.WARN)
    end

    if subcmd[args[1]] then
      local subsubcmd_name = table.remove(args, 1)
      local subsubcmd = subcmd[subsubcmd_name]

      if type(subsubcmd) ~= "function" then
        return notify(
          ("[Neotest] unknown subcommand: %s %s"):format(subcmd_name, subsubcmd_name),
          levels.WARN
        )
      end

      return subsubcmd(make_params(info, args))
    end

    if not subcmd[1] then
      return notify("[Neotest] missing subcommand", levels.WARN)
    end

    return subcmd[1](make_params(info, args))
  end

  if not cmd[1] then
    return notify("[Neotest] missing subcommand", levels.WARN)
  end

  return cmd[1](make_params(info, args))
end, {
  bang = true,
  nargs = "*",
  range = true,
  complete = function(_, cmd_line)
    local args = vim.split(cmd_line, "%s+", { trimempty = true })
    local last_idx = #args
    local last_arg = args[last_idx]

    local is_partial = not string.match(cmd_line, "%s$")

    local cmd_scope = ""

    -- command
    if last_idx == 1 then
      return cmd_completion_store[cmd_scope]
    elseif last_idx == 2 and is_partial then
      return vim.tbl_filter(function(cmd)
        return not not string.find(cmd, "^" .. last_arg)
      end, cmd_completion_store[cmd_scope])
    end

    -- sub-command
    cmd_scope = args[2]
    if last_idx == 2 and cmd_completion_store[cmd_scope] then
      return cmd_completion_store[cmd_scope]
    elseif #args == 3 and is_partial and cmd_completion_store[cmd_scope] then
      local items = vim.tbl_filter(function(cmd)
        return not not string.find(cmd, "^" .. last_arg)
      end, cmd_completion_store[cmd_scope])
      if #items > 0 then
        return
      end
    end

    -- sub-sub-command
    cmd_scope = (("%s:%s"):format(args[2], args[3]))
    if last_idx == 3 and cmd_completion_store[cmd_scope] then
      return cmd_completion_store[cmd_scope]
    elseif #args == 4 and is_partial and cmd_completion_store[cmd_scope] then
      local items = vim.tbl_filter(function(cmd)
        return not not string.find(cmd, "^" .. last_arg)
      end, cmd_completion_store[cmd_scope])
      if #items > 0 then
        return
      end
    end

    -- adpaters
    if string.match(last_arg, "^adapter=") and is_partial then
      return opt_completion_store.adapter(last_arg)
    end

    -- strategies
    if string.match(last_arg, "^strategy=") and is_partial then
      return opt_completion_store.strategy(last_arg)
    end
  end,
})
