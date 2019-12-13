require('strict').on()
local lust = require(debug.sourcedir()..'.lust')

local files = {
  'parse',
  'rules'
}

for i, file in ipairs(files) do
  dofile('tests/' .. file .. '.lua')
  if next(files, i) then
    print()
  end
end

local red = string.char(27) .. '[31m'
local green = string.char(27) .. '[32m'
local normal = string.char(27) .. '[0m'

if lust.errors > 0 then
  io.write(red .. lust.errors .. normal .. ' failed, ')
end

print(green .. lust.passes .. normal .. ' passed')

if lust.errors > 0 then os.exit(1) end
