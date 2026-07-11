shared.vapereload = true
local folder = shared.BadVapeFolder or 'badvape'
local chunk, loadError = loadstring(readfile(folder..'/os.luau'), folder..'/os.luau')
if type(chunk) ~= 'function' then
	error(loadError or 'BadVape runtime rejected', 0)
end
return chunk(...)
