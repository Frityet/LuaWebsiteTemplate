#!/usr/bin/env luajit
local log = require("server.log")

local LUAJS_PATH = "LuaJS"

---@param cmd string
---@param ... string
---@return boolean, string?
local function execute(cmd, ...)
    local cmd = cmd .. " " .. table.concat({...}, " ")
    log.info("$ ", cmd)

    ---Lua 5.2>= return `status`, `exitcode`, `signal`
    ---Lua 5.1 just returns `exitcode`
    ---@type (true | nil | integer), nil, integer?
    local status, _, code = os.execute(cmd)
    if type(status) == "boolean" or type(status) == "nil" then
        return not not status, status and nil or string.format("Error executing `%s`: %d", cmd, assert(code))
    else
        return status == 0, status == 0 and nil or string.format("Error executing `%s`: %d", cmd, status)
    end
end

---@param cmd string
---@param ... string
local function exec(cmd, ...) return assert(execute(cmd, ...)) end

local function compile_luajs()
    exec("git", "submodule", "update", "--init", "--recursive")
    ---@param cmd string
    ---@param ... string
    local function lj_exec(cmd, ...) return exec("cd", LUAJS_PATH, "&&", cmd, ...) end

    lj_exec "git reset --hard"
    lj_exec "git pull origin main --rebase"
    lj_exec "npm install"
    lj_exec "npm run clean"
    lj_exec("npm run build", "INSTALL_DEST="..LUAJS_PATH.."/build")
end

---@param path string
---@return boolean
local function file_exists(path) return os.rename(path, path) and true or false end

local CONFIG_54_FMT = [[
local working_dir = "%s"

variables = {
   AR = "emar",
   CC = "emcc",
   CFLAGS = "-fblocks -O2 -s WASM -s SIDE_MODULE -s ASYNCIFY",
   CXX = "em++",
   LD = "emcc",
   LIBFLAG = "-s WASM -s SIDE_MODULE -s ASYNCIFY",
   LIB_EXTENSION = "wasm",

   LUA_DIR = working_dir.."/LuaJS/lua",
   LUA_INCDIR = working_dir.."/LuaJS/lua",
   LUA_LIBDIR = working_dir.."/LuaJS/build/luajs",
   LUA_LIBDIR_FILE = "luajs.wasm",
   MAKE = "emmake make",
   RANLIB = "emranlib",
   STRIP = "emstrip"
}
]]

if not file_exists(LUAJS_PATH.."/build/luajs/luajs.wasm") then
    compile_luajs()
else
    log.info "LuaJS already compiled, skipping..."
end

local f = assert(io.popen("pwd", "r"))
local pwd = (f:read "*a"):sub(1, -2)
f:close()

f = assert(io.open(".luarocks/config-5.4.lua", "w+b"))
f:write(CONFIG_54_FMT:format(pwd))
f:close()

exec "./web-luarocks init client --no-wrapper-scripts"
exec "./web-luarocks make"

exec "./server-luarocks init server --no-wrapper-scripts"
exec "./server-luarocks make"

log.success "Successfully compiled LuaJS and created the LuaRocks scripts"
