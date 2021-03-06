-- CPaste, micro pastebin running on Carbon
print("Morning, Ladies and Gentlemen, CPaste here.")
-- Settings:
settings = assert(loadfile("settings.lua")())
-- Web Paste
webpaste_f, err = loadfile("themes/"..settings.theme.."/webpaste.lua")
if not err then
	webpaste = webpaste_f(settings)
else
	error(err)
end
-- Load css
local css = ""
local f = io.open("thirdparty/highlight.css")
if f then
	print("Read thirdparty/highlight.css")
	css = f:read("*a")
	f:close()
end
-- Actual Code:
srv.GET("/", mw.echo(settings.mainpage)) -- Main page.
srv.GET("/paste", mw.echo(webpaste))

getplain = mw.new(function() -- Main Retrieval of Pastes.
	local seg1 = params("seg1")
	local seg2 = params("seg2")
	local id = seg2
	local method = "pretty"
	if id == nil then
		id = seg1
	else
		method = seg1
		id = seg2
		if id == nil then
			content("No such paste.", 404, "text/plain")
			return
		end
		id = id:sub(2, -1)
	end
	if #id ~= 8 or id == nil then
		content("No such paste.", 404, "text/plain")
	else
		local con, err = redis.connectTimeout(redis_addr, 10) -- Connect to Redis
		if err ~= nil then error(err) end
		local res,err = con.Cmd("get", "cpaste:"..id).String() -- Get cpaste:<ID>
		if err ~= nil then error(err) end
		local cpastemdata, err = con.Cmd("get", "cpastemdata:"..id).String()
		if err ~= nil then error(err) end
		if res == "<nil>" then
			content(doctype()(
				tag"head"(
					tag"title" "CPaste"
				),
				tag"body"(
					"No such paste."
				)
			))
		else
			if method == "raw" then
				content(res, 200, "text/plain")
			elseif method == "pretty" or method == "hl" then
				if cpastemdata == "html" then
					content(res)
				elseif cpastemdata == "plain" then
					content(syntaxhl(res, hlcss), 200)
				else
					content(res, 200, cpastemdata)
				end
			else
				content("No such action. (Try 'raw' or 'pretty')", 404)
			end
		end
		con.Close()
	end
end, {redis_addr=settings.redis, url=settings.url, hlcss=css})

srv.GET("/p/:seg1", getplain)
srv.GET("/p/:seg1/*seg2", getplain)

srv.POST("/", mw.new(function() -- Putting up pastes
	local data = form("c") or form("f")
	local type = form("type") or "plain"
	local expire = tonumber(form("expire")) or expiretime
	local giveraw = false
	local giverawform = form("raw")
	if giverawform == "true" or giverawform == "yes" or giverawform == "y" then
		giveraw = true
	else
		giveraw = false
	end
	expire = expire * 60 --Convert the expiration time from minutes to seconds
	if expire > expiretime then --Prevent the expiration time getting too high
		expire = expiretime
	end
	if data then
		if #data <= maxpastesize then
			math.randomseed(unixtime())
			local id = ""
			local stringtable={}
			for i=1,8 do
				local n = math.random(48, 122)
				if (n < 58 or n > 64) and (n < 91 or n > 96) then
					id = id .. string.char(n)
				else
					id = id .. string.char(math.random(97, 122))
				end
			end
			local con, err = redis.connectTimeout(redis_addr, 10) -- Connect to Redis
			if err ~= nil then error(err) end
			local r, err = con.Cmd("set", "cpaste:"..id, data) -- Set cpaste:<randomid> to data
			if err ~= nil then error(err) end
			local r, err = con.Cmd("set", "cpastemdata:"..id, type) -- Set cpastemdata:<randomid> to the metadata
			if err ~= nil then error(err) end
			local r, err = con.Cmd("expire", "cpaste:"..id, expire) -- Make it expire
			if err ~= nil then error(err) end
			local r, err = con.Cmd("expire", "cpastemdata:"..id, expire) -- Make it expire
			if err ~= nil then error(err) end
			con.Close()
			if giveraw then
				content(url.."p/raw/"..id.."\n", 200, "text/plain")
			else
				content(url.."p/"..id.."\n", 200, "text/plain")
			end
		else
			content("Content too big. Max is "..tostring(maxpastesize).." Bytes, given "..tostring(#data).." Bytes.", 400, "text/plain")
		end
	else
		content("No content given.", 400, "text/plain")
	end
end, {url=settings.url, expiretime=settings.expiresecs, redis_addr=settings.redis, maxpastesize=settings.maxpastesize}))

print("Ready for action!")
