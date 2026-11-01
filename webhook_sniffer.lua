-- Luau | webhook_sniffer.lua | Roblox executor (hookfunction, hookmetamethod, getnamecallmethod, setclipboard optional)
-- standalone: run this BEFORE the script you want to check. prints every outbound request, flags likely exfil, copies webhook URL to clipboard.
local Players = game:GetService("Players")
local LP = Players.LocalPlayer

local MALICIOUS_HINTS = {
    "discord.com/api/webhooks", "discordapp.com/api/webhooks", "webhook", "iplogger", "grabber",
    "2no.co", "blasze", "webhook.site", "pipedream.net", "telegram.org/bot"
}
local SAFE_DOMAINS = {"roblox.com", "roproxy.com", "rbxcdn.com", "github.com", "githubusercontent.com", "gitlab.com"}

local function host_of(url)
    local h = string.match(string.lower(url), "^%a+://([^/]+)") or string.match(string.lower(url), "^([^/]+)")
    return h and (string.match(h, "^([^:]+)") or h) or ""
end
local function is_safe(url)
    local h = host_of(url)
    for _, d in ipairs(SAFE_DOMAINS) do
        if h == d or h:sub(-#d - 1) == "." .. d then return true end
    end
    return false
end
local function flag(url, body)
    local hay = (string.lower(url or "") .. " " .. string.lower(type(body) == "string" and body or ""))
    for _, h in ipairs(MALICIOUS_HINTS) do
        if hay:find(h, 1, true) then return true, h end
    end
    return false
end
local function clean_webhook(url)
    local u = (url or ""):gsub("\\/", "/")
    local dom, id, tok = u:match("(discord[%w%.]*/api/webhooks)/(%d+)/([^%s\"'%&<>]+)")
    if dom and id and tok then return "https://" .. dom .. "/" .. id .. "/" .. tok end
end

local seen = {}
local function report(kind, url, body)
    local hit, why = flag(url, body)
    local safe = is_safe(url or "")
    local tag = hit and "SUSPICIOUS" or (safe and "safe" or "unknown-domain")
    print(("[sniffer] %s %s -> %s"):format(kind, tag, tostring(url)))
    if body and #tostring(body) > 0 and #tostring(body) < 2000 then
        print("[sniffer]   body: " .. tostring(body))
    end
    if hit then
        local wh = clean_webhook(url) or clean_webhook(type(body) == "string" and body or "")
        if wh and not seen[wh] then
            seen[wh] = true
            warn("[sniffer] WEBHOOK CAPTURED: " .. wh)
            if setclipboard then
                pcall(setclipboard, wh)
                print("[sniffer] copied to clipboard")
            end
        end
        warn(("[sniffer] matched pattern: %s (reason: %s)"):format(why, kind))
    end
end

-- hook request-style functions (request/http_request/syn.request/http.request)
local function wrap(fn)
    return function(data, ...)
        if type(data) == "table" then
            report("request", data.Url or data.url or data.URL, data.Body or data.body)
        end
        return fn(data, ...)
    end
end
local raw = request or http_request or (syn and syn.request) or (http and http.request)
if raw and hookfunction then
    local orig = hookfunction(raw, wrap(raw))
    getgenv().request = wrap(orig)
    getgenv().http_request = getgenv().request
    if syn and syn.request then pcall(hookfunction, syn.request, wrap(orig)) end
    if http and http.request then pcall(hookfunction, http.request, wrap(orig)) end
    print("[sniffer] hooked request()")
else
    print("[sniffer] no request() hook available on this executor")
end

-- hook HttpGet / HttpService:PostAsync (common native exfil path the other anti-stealer MISSES)
local ok1 = pcall(function()
    local orig = game.HttpGet
    hookfunction(orig, function(self, url, ...)
        report("HttpGet", url, nil)
        return orig(self, url, ...)
    end)
end)
local ok2 = pcall(function()
    local HttpService = game:GetService("HttpService")
    local orig = HttpService.PostAsync
    hookfunction(orig, function(self, url, body, ...)
        report("PostAsync", url, body)
        return orig(self, url, body, ...)
    end)
end)
local ok3 = pcall(function()
    local HttpService = game:GetService("HttpService")
    local orig = HttpService.RequestAsync
    hookfunction(orig, function(self, opts, ...)
        if type(opts) == "table" then report("RequestAsync", opts.Url, opts.Body) end
        return orig(self, opts, ...)
    end)
end)
print(("[sniffer] HttpGet hook: %s | PostAsync hook: %s | RequestAsync hook: %s"):format(tostring(ok1), tostring(ok2), tostring(ok3)))

-- WebSocket (less common but used by some loaders)
local ws = WebSocket and WebSocket.connect
if ws and hookfunction then
    pcall(function()
        hookfunction(ws, function(url, ...)
            report("WebSocket", url, nil)
            return ws(url, ...)
        end)
    end)
end

print("[sniffer] armed. now run the script you want to check — every outbound call prints here, webhook (if any) gets flagged and copied.")
