----------------------------------------------------------------------
-- Juju — the signed community pack (fellesdata) and how it is checked
--
-- GitHub's robot signs SharedData (tools/jujusign.py, RSA-2048, e = 3,
-- PKCS#1 v1.5 + SHA-256). Any Juju can pass a pack on in-game (Sync.lua);
-- the receiver only uses it if the signature matches the public key in
-- PubKey.lua. Changing a single number breaks the signature.
--
-- Check without division: the signature has s and q with  s^3 = m + q*n
-- (m = padded hash), so only big-number multiply, add and compare are needed.
----------------------------------------------------------------------
local _, J = ...
local P = {}
J.Pack = P

local floor = math.floor
local TWO32 = 4294967296

----------------------------------------------------------------------
-- 32-bit and/xor: WoW's bit library, or small lookup tables (tests)
----------------------------------------------------------------------
local band, bxor
if type(bit) == "table" and bit.band and bit.bxor then
    band = function(a, b) return bit.band(a, b) % TWO32 end
    bxor = function(a, b) return bit.bxor(a, b) % TWO32 end
else
    local AND, XOR = {}, {}
    for a = 0, 15 do
        AND[a], XOR[a] = {}, {}
        for b = 0, 15 do
            local r1, r2, m = 0, 0, 1
            local x, y = a, b
            for _ = 1, 4 do
                local p, q = x % 2, y % 2
                if p == 1 and q == 1 then r1 = r1 + m end
                if p ~= q then r2 = r2 + m end
                x, y, m = floor(x / 2), floor(y / 2), m * 2
            end
            AND[a][b], XOR[a][b] = r1, r2
        end
    end
    local function op(t, a, b)
        local r, m = 0, 1
        for _ = 1, 8 do
            r = r + t[a % 16][b % 16] * m
            a, b, m = floor(a / 16), floor(b / 16), m * 16
        end
        return r
    end
    band = function(a, b) return op(AND, a, b) end
    bxor = function(a, b) return op(XOR, a, b) end
end

local function rrot(x, n)
    local lo = x % 2 ^ n
    return floor(x / 2 ^ n) + lo * 2 ^ (32 - n)
end
local function bnot(x) return TWO32 - 1 - x end

----------------------------------------------------------------------
-- SHA-256
----------------------------------------------------------------------
local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

function P.SHA256(msg)
    local len = #msg
    msg = msg .. "\128" .. string.rep("\0", (55 - len) % 64)
    local bits = len * 8
    local tail = {}
    for i = 8, 1, -1 do tail[i] = string.char(bits % 256); bits = floor(bits / 256) end
    msg = msg .. table.concat(tail)
    local h0, h1, h2, h3 = 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a
    local h4, h5, h6, h7 = 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    local w = {}
    for chunk = 1, #msg, 64 do
        for i = 0, 15 do
            local a, b, c, d = msg:byte(chunk + i * 4, chunk + i * 4 + 3)
            w[i] = ((a * 256 + b) * 256 + c) * 256 + d
        end
        for i = 16, 63 do
            local x, y = w[i - 15], w[i - 2]
            local s0 = bxor(bxor(rrot(x, 7), rrot(x, 18)), floor(x / 8))
            local s1 = bxor(bxor(rrot(y, 17), rrot(y, 19)), floor(y / 1024))
            w[i] = (w[i - 16] + s0 + w[i - 7] + s1) % TWO32
        end
        local a, b, c, d, e, f, g, h = h0, h1, h2, h3, h4, h5, h6, h7
        for i = 0, 63 do
            local S1 = bxor(bxor(rrot(e, 6), rrot(e, 11)), rrot(e, 25))
            local ch = bxor(band(e, f), band(bnot(e), g))
            local t1 = (h + S1 + ch + K[i + 1] + w[i]) % TWO32
            local S0 = bxor(bxor(rrot(a, 2), rrot(a, 13)), rrot(a, 22))
            local maj = bxor(bxor(band(a, b), band(a, c)), band(b, c))
            local t2 = (S0 + maj) % TWO32
            h, g, f, e = g, f, e, (d + t1) % TWO32
            d, c, b, a = c, b, a, (t1 + t2) % TWO32
        end
        h0, h1, h2, h3 = (h0 + a) % TWO32, (h1 + b) % TWO32, (h2 + c) % TWO32, (h3 + d) % TWO32
        h4, h5, h6, h7 = (h4 + e) % TWO32, (h5 + f) % TWO32, (h6 + g) % TWO32, (h7 + h) % TWO32
    end
    return ("%08x%08x%08x%08x%08x%08x%08x%08x"):format(h0, h1, h2, h3, h4, h5, h6, h7)
end

----------------------------------------------------------------------
-- Big numbers: little-endian arrays of 24-bit limbs
----------------------------------------------------------------------
local BASE = 16777216          -- 2^24: a limb product (< 2^48) plus carries stays exact in a double

local function trim(a)
    while #a > 1 and a[#a] == 0 do a[#a] = nil end
    return a
end

local function fromHex(h)
    if type(h) ~= "string" or h == "" or h:find("[^0-9a-fA-F]") then return nil end
    local a = {}
    local i = #h
    while i >= 1 do
        local j = math.max(1, i - 5)
        a[#a + 1] = tonumber(h:sub(j, i), 16)
        i = j - 1
    end
    return trim(a)
end

local function mul(a, b)
    local r = {}
    for i = 1, #a + #b do r[i] = 0 end
    for i = 1, #a do
        local carry, ai = 0, a[i]
        for j = 1, #b do
            local t = r[i + j - 1] + ai * b[j] + carry
            carry = floor(t / BASE)
            r[i + j - 1] = t - carry * BASE
        end
        local k = i + #b
        while carry > 0 do
            local t = r[k] + carry
            carry = floor(t / BASE)
            r[k] = t - carry * BASE
            k = k + 1
        end
    end
    return trim(r)
end

local function add(a, b)
    local r, carry = {}, 0
    for i = 1, math.max(#a, #b) do
        local t = (a[i] or 0) + (b[i] or 0) + carry
        carry = floor(t / BASE)
        r[i] = t - carry * BASE
    end
    if carry > 0 then r[#r + 1] = carry end
    return trim(r)
end

local function cmp(a, b)
    if #a ~= #b then return #a < #b and -1 or 1 end
    for i = #a, 1, -1 do
        if a[i] ~= b[i] then return a[i] < b[i] and -1 or 1 end
    end
    return 0
end

local DIGEST_INFO = "3031300d060960864801650304020105000420"

-- true if sig = { s = hex, q = hex } is a valid signature of text
function P.Verify(text, sig)
    if type(text) ~= "string" or type(sig) ~= "table" or not J.PUBKEY_N then return false end
    local n, s, q = fromHex(J.PUBKEY_N), fromHex(sig.s), fromHex(sig.q)
    if not (n and s and q) or cmp(s, n) >= 0 or (#s == 1 and s[1] == 0) then return false end
    local k = math.ceil(#J.PUBKEY_N:gsub("^0+", "") / 2)                 -- modulus length in bytes
    local t = DIGEST_INFO .. P.SHA256(text)
    local em = "0001" .. string.rep("ff", k - #t / 2 - 3) .. "00" .. t
    local m = fromHex(em)
    return cmp(mul(mul(s, s), s), add(m, mul(q, n))) == 0
end

----------------------------------------------------------------------
-- The text that is signed (must match tools/merge_submissions.py)
----------------------------------------------------------------------
function P.Canonical(version, shared, contrib)
    local npcs, ids, lines = {}, {}, {}
    for npc in pairs(shared) do npcs[#npcs + 1] = npc end
    table.sort(npcs)
    for _, npc in ipairs(npcs) do lines[#lines + 1] = npc .. "=" .. shared[npc] end
    for id in pairs(contrib) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do lines[#lines + 1] = "#" .. id .. "=" .. contrib[id] end
    return "JUJUPACK1\nversion=" .. version .. "\n" .. (#lines > 0 and (table.concat(lines, "\n") .. "\n") or "")
end

-- canonical text -> version, shared, contrib (strict: anything odd = nil)
function P.Parse(text)
    if type(text) ~= "string" or #text > 2000000 then return nil end
    local version
    local shared, contrib = {}, {}
    local first = true
    for line in text:gmatch("([^\n]*)\n") do
        if first then
            if line ~= "JUJUPACK1" then return nil end
            first = false
        elseif not version then
            version = tonumber(line:match("^version=(%d+)$"))
            if not version then return nil end
        else
            local npc, raw = line:match("^(%d+)=(%d+|%d+|[0-9:,]*)$")
            if npc then
                shared[tonumber(npc)] = raw
            else
                local id, serial = line:match("^#([0-9a-f]+)=(%d+)$")
                if not id then return nil end
                contrib[id] = tonumber(serial)
            end
        end
    end
    if not version then return nil end
    return version, shared, contrib
end

----------------------------------------------------------------------
-- Which pack is in use: the one shipped in SharedData.lua, or a newer
-- signed one received in-game (kept in JujuDB.pack)
----------------------------------------------------------------------
function P.Current()
    local file = { version = J.SHARED_VERSION or 0, sig = J.SHARED_SIG }
    local db = J.db and J.db.pack
    if db and db.version and db.version > file.version then return db.version, db.sig, "mottatt" end
    return file.version, file.sig, "fil"
end

-- the text to hand on to another player (canonical + signature), or nil
function P.Outgoing()
    local version, sig = P.Current()
    if not sig or version == 0 then return nil end
    local text = P.Canonical(version, J.SHARED or {}, J.SHARED_CONTRIB or {})
    return version, text .. "!s=" .. sig.s .. "\n!q=" .. sig.q .. "\n"
end

-- use a received pack: check signature, store it, switch to it
function P.Accept(wire)
    local s = wire:match("\n!s=([0-9a-f]+)\n")
    local q = wire:match("\n!q=([0-9a-f]+)\n$")
    local cut = wire:find("\n!s=", 1, true)
    if not (s and q and cut) then return false, "mangler signatur" end
    local text = wire:sub(1, cut)
    local version, shared, contrib = P.Parse(text)
    if not version then return false, "ugyldig format" end
    if version <= (P.Current()) then return false, "not newer" end
    if not P.Verify(text, { s = s, q = q }) then return false, "bad signature" end
    J.db.pack = { version = version, text = text, sig = { s = s, q = q }, t = time() }
    P.Apply()
    return true
end

-- switch J.SHARED to the stored pack if it is newer than the shipped one
function P.Apply()
    local db = J.db and J.db.pack
    if not (db and db.text and db.version and db.version > (J.SHARED_VERSION or 0)) then return end
    local version, shared, contrib = P.Parse(db.text)
    if not version then J.db.pack = nil; return end
    J.SHARED, J.SHARED_CONTRIB = shared, contrib
    J.SHARED_VERSION_ACTIVE = version
    if J.ResetSharedCache then J.ResetSharedCache() end
    if J.PeersChanged then J.PeersChanged() end
end
