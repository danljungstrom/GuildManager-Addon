-- Guildion -- core/base64.lua
-- Standard base64 (RFC 4648: A-Z a-z 0-9 + /, padded with =), the alphabet the app's
-- decoder accepts. Plain arithmetic: Lua 5.1 has no bit operators.
local _, GM = ...

GM.base64 = {}
local base64 = GM.base64

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local CHARS = {}
for i = 1, 64 do
  CHARS[i - 1] = string.sub(ALPHABET, i, i)
end

function base64.Encode(data)
  local out = {}
  local length = #data
  for i = 1, length - 2, 3 do
    local a, b, c = string.byte(data, i, i + 2)
    local n = a * 65536 + b * 256 + c
    out[#out + 1] = CHARS[math.floor(n / 262144)]
      .. CHARS[math.floor(n / 4096) % 64]
      .. CHARS[math.floor(n / 64) % 64]
      .. CHARS[n % 64]
  end

  local rest = length % 3
  if rest == 1 then
    local n = string.byte(data, length) * 65536
    out[#out + 1] = CHARS[math.floor(n / 262144)] .. CHARS[math.floor(n / 4096) % 64] .. "=="
  elseif rest == 2 then
    local a, b = string.byte(data, length - 1, length)
    local n = a * 65536 + b * 256
    out[#out + 1] = CHARS[math.floor(n / 262144)]
      .. CHARS[math.floor(n / 4096) % 64]
      .. CHARS[math.floor(n / 64) % 64]
      .. "="
  end
  return table.concat(out)
end
