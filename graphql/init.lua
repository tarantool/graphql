local ok, VERSION = pcall(require, 'graphql.VERSION')
if not ok then
    VERSION = 'unknown'
end

return { VERSION = VERSION }
