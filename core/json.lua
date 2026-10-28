-- Guildion -- core/json.lua
-- JSON encoder only. The output is byte-stable: object keys are sorted, numbers have one
-- spelling. A table is an array ONLY when the builder marked it with json.Array; every other
-- table is an object. Table shape is never guessed, so an empty list still encodes as [].
local _, GM = ...

GM.json = {}
local json = GM.json

local ARRAY = {}

-- Encodes as null.
json.null = setmetatable({}, {
  __tostring = function()
    return "null"
  end,
})

-- Marks `list` (1..n, no holes) as a JSON array and returns it.
function json.Array(list)
  return setmetatable(list, ARRAY)
end

local SHORT = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function EscapeChar(char)
  return SHORT[char] or string.format("\\u%04x", string.byte(char))
end

-- Escapes quote, backslash and the control characters. The class is spelled out rather than
-- written as %c, which asks the C library and so depends on the client's locale: under a ctype
-- table that calls 0x80-0x9f control characters, %c would escape the middle of a UTF-8 name.
-- Bytes >= 0x80 pass through: Lua strings from the game are UTF-8 and JSON text is UTF-8.
local CONTROL = '[%z\1-\31\127"\\]'

local function EncodeString(text)
  return '"' .. string.gsub(text, CONTROL, EscapeChar) .. '"'
end

local function EncodeNumber(n)
  if n ~= n or n == math.huge or n == -math.huge then
    error("json: cannot encode " .. tostring(n))
  end
  if n == math.floor(n) then
    return string.format("%.0f", n) -- never 1.79e+09, never 60.0
  end
  return string.format("%.14g", n)
end

local Encode

local function EncodeArray(list)
  local parts = {}
  for i = 1, #list do
    parts[i] = Encode(list[i])
  end
  return "[" .. table.concat(parts, ",") .. "]"
end

local function EncodeObject(object)
  local keys = {}
  for key in pairs(object) do
    if type(key) ~= "string" then
      error("json: object key must be a string, got " .. type(key))
    end
    keys[#keys + 1] = key
  end
  table.sort(keys)
  local parts = {}
  for i = 1, #keys do
    parts[i] = EncodeString(keys[i]) .. ":" .. Encode(object[keys[i]])
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

Encode = function(value)
  local kind = type(value)
  if value == json.null then
    return "null"
  elseif kind == "string" then
    return EncodeString(value)
  elseif kind == "number" then
    return EncodeNumber(value)
  elseif kind == "boolean" then
    return value and "true" or "false"
  elseif kind == "table" then
    if getmetatable(value) == ARRAY then
      return EncodeArray(value)
    end
    return EncodeObject(value)
  end
  error("json: cannot encode a " .. kind)
end

json.Encode = Encode
