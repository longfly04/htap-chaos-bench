#!/usr/bin/env sysbench

sysbench.cmdline.options = {
   sql_file = {"Path to the TP SQL file", ""},
   batch_size = {"Batch size value used in the SQL template", 128},
   hot_modulus = {"Hot modulus value used in the SQL template", 64},
   hot_remainder = {"Hot remainder value used in the SQL template", 1},
   progress_file = {"CSV file receiving intermediate TP progress rows", ""}
}

local drv
local con
local rendered_sql

local function trim(value)
   return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function load_sql(path)
   local fh = assert(io.open(path, "r"))
   local content = fh:read("*a")
   fh:close()

   local lines = {}
   for raw_line in content:gmatch("([^\n]*)\n?") do
      if raw_line == "" and #lines > 0 and lines[#lines] == "" then
         break
      end
      local line = trim(raw_line)
      if not line:match("^\\set%s+") then
         table.insert(lines, raw_line)
      end
   end

   local sql = table.concat(lines, "\n")
   local replacements = {
      batch_size = tostring(sysbench.opt.batch_size),
      hot_modulus = tostring(sysbench.opt.hot_modulus),
      hot_remainder = tostring(sysbench.opt.hot_remainder),
   }

   sql = sql:gsub(":([A-Za-z_][A-Za-z0-9_]*)", function(name)
      local value = replacements[name]
      if value == nil then
         error(string.format("unsupported SQL placeholder :%s in %s", name, path))
      end
      return value
   end)
   return sql
end

function thread_init()
   if sysbench.opt.sql_file == "" then
      error("--sql-file is required")
   end
   drv = sysbench.sql.driver()
   con = drv:connect()
   rendered_sql = load_sql(sysbench.opt.sql_file)
end

function event()
   con:query(rendered_sql)
end

function thread_done()
   if con ~= nil then
      con:disconnect()
      con = nil
   end
end

function sysbench.hooks.report_intermediate(stat)
   if sysbench.opt.progress_file == "" then
      return
   end
   local seconds = stat.time_interval
   local tps = 0
   local latency_ms = 0
   if seconds > 0 then
      tps = stat.events / seconds
   end
   if stat.events > 0 and seconds > 0 then
      latency_ms = (seconds / stat.events) * 1000.0
   end
   local fh = assert(io.open(sysbench.opt.progress_file, "a"))
   fh:write(string.format("%.3f,%.6f,%.6f,sysbench\n", stat.time_total, tps, latency_ms))
   fh:close()
end
