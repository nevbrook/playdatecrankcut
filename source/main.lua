-- CRANK CUT: a video-editing game for the Playdate
-- Edit the cut. Land the hook. Go viral.
import "CoreLibs/graphics"

local pd <const> = playdate
local gfx <const> = pd.graphics
local snd <const> = pd.sound
local floor, ceil, abs, min, max = math.floor, math.ceil, math.abs, math.min, math.max
local sin, cos, pi, exp, sqrt = math.sin, math.cos, math.pi, math.exp, math.sqrt
local random = math.random

pd.display.setRefreshRate(30)
math.randomseed(pd.getSecondsSinceEpoch())

local BLACK, WHITE = gfx.kColorBlack, gfx.kColorWhite
local PX, PY, PW, PH = 6, 20, 262, 136 -- preview window
local GEAR = 4 -- crank degrees per frame scrubbed

local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end

---------------------------------------------------------------- sound
local function mk(wave, a, d, s, r)
	local sy = snd.synth.new(wave)
	sy:setADSR(a, d, s, r)
	return sy
end
local sKick = mk(snd.kWaveSine, 0, 0.12, 0, 0.05)
local sTick = mk(snd.kWaveSquare, 0, 0.015, 0, 0.01)
local sHat = mk(snd.kWaveNoise, 0, 0.02, 0, 0.01)
local sChunk = mk(snd.kWaveNoise, 0, 0.09, 0, 0.04)
local sLead = mk(snd.kWaveTriangle, 0, 0.18, 0.2, 0.1)
local function note(sy, hz, len, vol) sy:playNote(hz, vol or 0.5, len or 0.05) end

local later = {}
local function after(frames, fn) later[#later + 1] = { t = frames, fn = fn } end
local function runLater()
	for i = #later, 1, -1 do
		local l = later[i]
		l.t = l.t - 1
		if l.t <= 0 then table.remove(later, i); l.fn() end
	end
end
local function fanfare()
	for i, hz in ipairs({ 392, 523, 659, 784 }) do after((i - 1) * 4, function() note(sLead, hz, 0.15, 0.6) end) end
end
local function sadTrombone()
	for i, hz in ipairs({ 247, 233, 220, 196 }) do after((i - 1) * 7, function() note(sLead, hz, 0.25, 0.5) end) end
end

---------------------------------------------------------------- text helpers
local bigCache, bigCount = {}, 0
local function bigText(str, x, y, scale, align)
	local img = bigCache[str]
	if not img then
		if bigCount > 80 then bigCache, bigCount = {}, 0 end
		img = gfx.imageWithText(str, 400, 30)
		bigCache[str] = img
		bigCount = bigCount + 1
	end
	local w, _ = img:getSize()
	local ox = 0
	if align == "c" then ox = w * scale / 2 elseif align == "r" then ox = w * scale end
	img:drawScaled(x - ox, y, scale)
end
local function txt(s, x, y) gfx.drawText(s, x, y) end
local function txtC(s, x, y) gfx.drawTextAligned(s, x, y, kTextAlignment.center) end
local function txtR(s, x, y) gfx.drawTextAligned(s, x, y, kTextAlignment.right) end
local function whiteText(fn) gfx.setImageDrawMode(gfx.kDrawModeFillWhite); fn(); gfx.setImageDrawMode(gfx.kDrawModeCopy) end

---------------------------------------------------------------- footage definitions
local TYPES = {}
local TYPE_ORDER = { "cook", "pet", "fail", "talk", "dance", "story" }

local function circ(x, y, r) gfx.fillCircleAtPoint(x, y, r) end
local function line(x1, y1, x2, y2, w) gfx.setLineWidth(w or 1); gfx.drawLine(x1, y1, x2, y2); gfx.setLineWidth(1) end

local function nearest(c, f)
	local bi, bd = 1, 1e9
	for i, m in ipairs(c.markers) do
		local d = f - m.f
		if abs(d) < abs(bd) then bi, bd = i, d end
	end
	return bi, bd
end

local function burst(x, y, r, d)
	local a = abs(d)
	if a > 6 then return end
	local rr = r * (0.6 + (6 - a) / 8)
	gfx.setColor(BLACK)
	for i = 0, 11 do
		local ang = i * pi / 6 + (a % 2) * 0.13
		line(x + cos(ang) * rr * 0.55, y + sin(ang) * rr * 0.55, x + cos(ang) * rr, y + sin(ang) * rr, 2)
	end
end

-- stick figure; (x,y) is the hip, angle rotates the whole body
local function stick(x, y, ang, armL, armR, spread, s)
	s = s or 1
	local ca, sa = cos(ang), sin(ang)
	local function P(px, py) return x + (px * ca - py * sa) * s, y + (px * sa + py * ca) * s end
	local hx, hy = P(0, -26)
	local nx, ny = P(0, -17)
	local x0, y0 = P(0, 0)
	gfx.setColor(BLACK)
	circ(hx, hy, 8 * s)
	line(nx, ny, x0, y0, 3)
	local ax, ay = P(-13, -17 + armL); line(nx, ny, ax, ay, 3)
	ax, ay = P(13, -17 + armR); line(nx, ny, ax, ay, 3)
	local lx, ly = P(-spread, 17); line(x0, y0, lx, ly, 3)
	lx, ly = P(spread, 17); line(x0, y0, lx, ly, 3)
end

local function sparkle(x, y, r)
	line(x - r, y, x + r, y); line(x, y - r, x, y + r)
	line(x - r * 0.6, y - r * 0.6, x + r * 0.6, y + r * 0.6); line(x - r * 0.6, y + r * 0.6, x + r * 0.6, y - r * 0.6)
end

local function drawCook(c, f)
	local m, d = nearest(c, f)
	gfx.setColor(BLACK)
	gfx.drawLine(0, 118, PW, 118)
	gfx.fillRect(70, 104, 120, 14)
	gfx.fillRect(98, 94, 64, 7)
	gfx.fillRect(160, 96, 48, 4)
	local last = (m == #c.markers)
	if last and d > 14 then
		-- the reveal: a plate with a hero dish
		gfx.setColor(BLACK)
		gfx.drawEllipseInRect(70, 70, 120, 34)
		gfx.fillEllipseInRect(95, 60, 70, 36)
		gfx.setColor(WHITE); gfx.fillEllipseInRect(105, 65, 20, 8); gfx.setColor(BLACK)
		for i = 1, 4 do
			local a = f * 0.2 + i * 1.6
			sparkle(130 + cos(a) * 70, 56 + sin(a) * 28, 3 + (f + i * 3) % 4)
		end
		return
	end
	local fy
	if abs(d) <= 14 then fy = 86 - 56 * (1 - (d / 14) ^ 2) else fy = 87 + sin(f * 0.6) * 1.5 end
	circ(130, fy, 8)
	gfx.setColor(WHITE); circ(127, fy - 3, 2); gfx.setColor(BLACK)
	if abs(d) > 14 then
		for i = 1, 3 do
			local x = 105 + i * 20
			line(x, 82, x + sin(f * 0.3 + i) * 5, 66, 1)
		end
	end
	burst(130, 38, 34, d)
end

local function drawPet(c, f)
	local m, d = nearest(c, f)
	local dx = 185
	gfx.setColor(BLACK)
	gfx.drawLine(0, 114, PW, 114)
	-- thrower
	local arm = (d >= -48 and d <= -38) and -14 or 6
	stick(24, 94, 0, arm, 4, 5, 1)
	local jy = 0
	if abs(d) <= 10 then jy = -36 * (1 - (d / 10) ^ 2) end
	local runphase = sin(f * 0.5)
	gfx.setColor(BLACK)
	gfx.fillEllipseInRect(dx - 20, 86 + jy, 40, 18)
	circ(dx + 22, 82 + jy, 9)
	gfx.fillTriangle(dx + 16, 76 + jy, dx + 22, 66 + jy, dx + 25, 76 + jy)
	line(dx - 16, 100 + jy, dx - 16 + runphase * 4, 114, 3)
	line(dx + 14, 100 + jy, dx + 14 - runphase * 4, 114, 3)
	line(dx - 20, 90 + jy, dx - 31, 76 + jy + sin(f * 0.5) * 6, 3)
	gfx.setColor(WHITE); circ(dx + 25, 80 + jy, 2); gfx.setColor(BLACK)
	if d >= -40 and d <= 0 then
		local t = (d + 40) / 40
		local fx = 30 + t * (dx + 26 - 30)
		local fy = 70 - 40 * sin(pi * t) * (1 - t) - (70 - (82 - 36)) * t * 0.9
		gfx.fillEllipseInRect(fx - 9, fy - 2, 18, 5)
	elseif d > 0 and d < 40 then
		gfx.fillEllipseInRect(dx + 20, 86 + jy, 18, 5)
	end
	burst(dx + 28, 50, 28 + 14 * m / #c.markers, d)
end

local function drawFail(c, f)
	local m, d = nearest(c, f)
	local w = c.markers[m].w
	gfx.setColor(BLACK)
	gfx.drawLine(0, 118, PW, 118)
	gfx.fillTriangle(40, 118, 74, 118, 74, 102)
	local x = 130 + d * 3
	if d < -20 then
		local y = 111
		if x > 40 and x < 74 then y = 111 - (x - 40) * 0.26 end
		gfx.fillRect(x - 14, 114, 28, 3)
		circ(x - 9, 119, 2); circ(x + 9, 119, 2)
		stick(x, y - 18, 0, 4, 4, 7, 0.8)
	elseif d < 0 then
		local t = (d + 20) / 20
		local h = 22 + 22 * w
		local y = 102 + 14 * t - h * 4 * t * (1 - t)
		local ang = t * 2 * pi * (w > 0.6 and 1 or 0.5)
		stick(x, y - 6, ang, -14, -14, 8, 0.8)
		line(x - 14, y + 12, x + 14, y + 12, 3)
	else
		stick(min(x, 160), 108, pi / 2, -10, 10, 8, 0.8)
		gfx.fillRect(168 + d, 112, 28, 3)
		if d < 30 then
			for i = 0, 2 do
				local a = d * 0.4 + i * 2.1
				sparkle(130 + cos(a) * 24, 88 + sin(a) * 8, 4)
			end
		end
	end
	burst(130, 100, 16 + 18 * w, d)
end

local function drawDance(c, f)
	local m, d = nearest(c, f)
	local beat = c.beat
	local bi = floor(f / beat)
	local pose = bi % 4
	local ph = (f % beat) / beat
	gfx.setColor(BLACK)
	gfx.drawCircleAtPoint(130, 80, 24 + ph * 60)
	gfx.drawLine(0, 124, PW, 124)
	local arms = { { -16, -16 }, { 10, 10 }, { -16, 8 }, { 8, -16 } }
	local legs = { 6, 14, 4, 14 }
	local sway = (pose % 2 == 0) and -12 or 12
	local jy = 0
	local a = arms[pose + 1]
	if abs(d) <= 7 then
		jy = -22 * (1 - (d / 7) ^ 2); a = { -18, -18 }
	end
	stick(130 + sway, 92 + jy, sway * 0.01, a[1], a[2], legs[pose + 1], 1.2)
	burst(130, 40, 40, d)
end

local function drawTalk(c, f)
	local m, d = nearest(c, f)
	gfx.setColor(BLACK)
	gfx.fillRect(80, 100, 100, 40)
	circ(130, 62, 30)
	gfx.setColor(WHITE)
	local speaking = (f % 160) < 110 or abs(d) < 14
	if (f % 70) < 3 then
		line(112, 56, 122, 56); line(138, 56, 148, 56)
	else
		circ(117, 56, 5); circ(143, 56, 5)
	end
	gfx.setColor(BLACK); circ(117, 57, 2); circ(143, 57, 2)
	local browUp = abs(d) < 12 and -8 or 0
	gfx.setColor(WHITE)
	line(110, 46 + browUp, 124, 44 + browUp, 2); line(136, 44 + browUp, 150, 46 + browUp, 2)
	local mh = 1
	if speaking then mh = 3 + 7 * abs(sin(f * 0.9)) end
	if abs(d) < 8 then mh = 14 end
	gfx.fillEllipseInRect(120, 70, 20, mh)
	gfx.setColor(BLACK)
	if not speaking then
		txt("...", 168, 30)
	end
	if c.id == "story" then
		for i = 0, floor(f / 90) do
			line(194, 24 + i * 10, 194 + 40 + (i * 13 % 16), 24 + i * 10, 2)
		end
	end
	burst(130, 62, 56, d)
end

TYPES.cook = { name = "Cooking / ASMR", len = 450, beat = 20, T = 90, draw = drawCook,
	marks = { { .30, .6 }, { .62, .7 }, { .92, 1 } },
	caps = { { "Wait for the reveal...", 1 }, { "Cooking a meal", .35 }, { "Dinner", .2 } } }
TYPES.pet = { name = "Pet clips", len = 360, beat = 15, T = 60, draw = drawPet,
	marks = { { .25, .4 }, { .68, 1 } },
	caps = { { "Watch the catch!", 1 }, { "My dog", .3 }, { "Dog does a thing", .5 } } }
TYPES.fail = { name = "Fail compilation", len = 420, beat = 12, T = 48, draw = drawFail,
	marks = { { .16, .4 }, { .34, .55 }, { .52, .7 }, { .70, .85 }, { .90, 1 } },
	caps = { { "He did NOT stick it", 1 }, { "Skate fail", .5 }, { "Ouch", .3 } } }
TYPES.talk = { name = "Hot takes", len = 480, beat = 18, T = 72, draw = drawTalk,
	marks = { { .22, .6 }, { .50, .8 }, { .82, 1 } },
	caps = { { "Hot take: you're wrong", 1 }, { "Opinion", .3 }, { "Talking", .1 } } }
TYPES.dance = { name = "Dance / trend", len = 480, beat = 15, T = 60, draw = drawDance,
	marks = { { .20, .6 }, { .42, .8 }, { .62, .8 }, { .90, 1 } },
	caps = { { "Do you know this one?", 1 }, { "dance", .3 }, { "New trend", .6 } } }
TYPES.story = { name = "Storytime", len = 600, beat = 20, T = 100, draw = drawTalk,
	marks = { { .15, .5 }, { .38, .7 }, { .62, .8 }, { .92, 1 } },
	caps = { { "Storytime: it gets worse", 1 }, { "Long story", .4 }, { "Story", .2 } } }

local function newClip(id)
	local t = TYPES[id]
	local c = { id = id, t = t, name = t.name, len = t.len, beat = t.beat, T = t.T, draw = t.draw, markers = {}, caps = {} }
	for _, m in ipairs(t.marks) do
		local pos = m[1] + (random() - 0.5) * 0.05
		local f = floor(pos * t.len / t.beat + 0.5) * t.beat
		if id ~= "dance" then f = f + random(-2, 2) end
		c.markers[#c.markers + 1] = { f = clamp(f, 40, t.len - 30), w = m[2] }
	end
	for _, cp in ipairs(t.caps) do c.caps[#c.caps + 1] = cp end
	for i = #c.caps, 2, -1 do
		local j = random(i)
		c.caps[i], c.caps[j] = c.caps[j], c.caps[i]
	end
	return c
end

local function interestAt(c, f)
	local v = 0.12
	for _, m in ipairs(c.markers) do
		local d = (f - m.f) / 22
		v = v + 0.9 * m.w * exp(-d * d)
	end
	return min(v, 1)
end

local function hookScore(c, f)
	local best = 0
	for _, m in ipairs(c.markers) do
		local d = m.f - f
		local s
		if d >= 0 and d <= 25 then s = 1
		elseif d < 0 then s = max(0, 0.8 + d / 40)
		else s = max(0, 1 - (d - 25) / 90) end
		best = max(best, s * (0.4 + 0.6 * m.w))
	end
	return best
end

local function beatDist(c, f)
	local r = f % c.beat
	return min(r, c.beat - r)
end

---------------------------------------------------------------- trends
local TRENDS = {
	{ id = "snappy", name = "Snappy cuts", desc = "Average cut gap under 0.8x target.",
		hit = function(m) if m.avgSeg <= 0.8 * m.T then return 1 elseif m.avgSeg <= m.T then return 0.5 end return 0 end },
	{ id = "synced", name = "Beat-synced", desc = "Land cuts within 2 frames of the beat.",
		hit = function(m) if m.sync <= 2 then return 1 elseif m.sync <= 4 then return 0.5 end return 0 end },
	{ id = "early", name = "Cold open", desc = "Open right before the payoff.",
		hit = function(m) if m.hs >= 0.85 then return 1 elseif m.hs >= 0.6 then return 0.5 end return 0 end },
	{ id = "caption", name = "Caption culture", desc = "Right words, readable timing.",
		hit = function(m) if m.capQ >= 0.8 then return 1 elseif m.capQ >= 0.5 then return 0.5 end return 0 end },
	{ id = "slow", name = "Slow burn", desc = "Longer cuts that still hold people.",
		hit = function(m) if m.avgSeg >= 1.2 * m.T and m.ret >= 0.5 then return 1 end return 0 end },
}

---------------------------------------------------------------- evaluation
local function evaluate(c, ed, trend, stale, followers)
	local len, T = c.len, c.T
	local cuts = {}
	for _, f in ipairs(ed.cuts) do cuts[#cuts + 1] = f end
	table.sort(cuts)
	local bounds = { 0 }
	for _, f in ipairs(cuts) do bounds[#bounds + 1] = f end
	bounds[#bounds + 1] = len
	local segLens = {}
	for i = 1, #bounds - 1 do segLens[i] = max(1, bounds[i + 1] - bounds[i]) end
	local nseg = #segLens

	local hs = hookScore(c, ed.hook or 0)
	local hookMult = 0.5 + 1.5 * hs

	local secs = ceil(len / 30)
	local r, ret = 1, { 1 }
	local worst, worstSec, dragSecs, jumpy = 0, 1, 0, 0
	local function segAt(f)
		for i = 1, nseg do if f < bounds[i + 1] then return i end end
		return nseg
	end
	local covered, missed = 0, 0
	for _, m in ipairs(c.markers) do
		local ok = false
		for _, cf in ipairs(cuts) do if abs(cf - m.f) <= 8 then ok = true end end
		m.covered = ok
		if ok then covered = covered + 1 else missed = missed + 1 end
	end
	for i = 1, secs do
		local f0 = (i - 1) * 30
		local L = segLens[segAt(f0 + 15)]
		local loss = 0.008
		local drag = max(0, L / T - 1.5)
		if drag > 0 then loss = loss + min(0.08, 0.03 * drag); dragSecs = dragSecs + 1 end
		if L < 0.35 * T then loss = loss + 0.02; jumpy = jumpy + 1 end
		loss = loss + 0.012 * (1 - interestAt(c, f0 + 15))
		if i <= 3 then loss = loss + (1 - hs) * 0.07 end
		for _, m in ipairs(c.markers) do
			if m.f >= f0 and m.f < f0 + 30 then
				if m.covered then loss = loss - 0.035 * m.w else loss = loss + 0.035 * m.w end
			end
		end
		r = clamp(r - loss, 0, 1)
		ret[i + 1] = r
		if loss > worst then worst, worstSec = loss, i end
	end
	local retention = r

	-- rhythm
	local mean = len / nseg
	local var = 0
	for _, L in ipairs(segLens) do var = var + (L - mean) ^ 2 end
	local cv = sqrt(var / nseg) / mean
	local e1 = abs(mean / T - 1)
	local rhythm = clamp(1.5 - 0.9 * (e1 * 0.8 + cv * 0.6), 0.5, 1.5)

	-- beat sync
	local syncD = 6.5
	if #cuts > 0 then
		local s = 0
		for _, f in ipairs(cuts) do s = s + beatDist(c, f) end
		syncD = s / #cuts
	end
	local syncMult = clamp(1.3 - 0.09 * syncD, 0.7, 1.3)

	-- caption
	local capQ, capMult, capNote = 0, 0.8, "No caption: left points on the table."
	if ed.capText then
		local fit = c.caps[ed.capText][2]
		local dur = ed.capE - ed.capS
		local durS
		if dur < 45 then durS = dur / 45 elseif dur <= 120 then durS = 1 else durS = max(0, 1 - (dur - 120) / 120) end
		local startS = ed.capS <= 90 and 1 or max(0.4, 1 - (ed.capS - 90) / 300)
		capQ = fit * 0.55 + durS * 0.3 + startS * 0.15
		capMult = 0.8 + 0.5 * capQ
		if fit < 0.6 then capNote = "Caption missed the point of the clip."
		elseif durS < 0.7 then capNote = (dur < 45) and "Caption flashed by too fast to read." or "Caption hung around and cluttered."
		elseif startS < 0.8 then capNote = "Caption came in late."
		else capNote = "Caption: right words, readable timing." end
	end

	-- trend
	local metrics = { avgSeg = mean, T = T, sync = syncD, hs = hs, capQ = capQ, ret = retention }
	local hit = trend.hit(metrics)
	local trendBonus = 0.5 * hit
	local trendLine
	if stale then
		trendBonus = -0.15 * hit
		trendLine = trend.name .. " is stale. Last week's trend."
	elseif hit >= 1 then trendLine = "Trend '" .. trend.name .. "': nailed it."
	elseif hit > 0 then trendLine = "Trend '" .. trend.name .. "': half in."
	else trendLine = "Trend '" .. trend.name .. "': ignored." end

	local viral = hookMult * retention * rhythm * capMult * syncMult * (1 + trendBonus)
	local views = floor(viral * (500 + followers * 8))
	local res = {
		hs = hs, hookMult = hookMult, ret = retention, retArr = ret, rhythm = rhythm, sync = syncMult,
		capMult = capMult, trendBonus = trendBonus, viral = viral, views = views,
		likes = floor(views * retention * 0.12), shares = floor(views * (0.01 + 0.05 * hs) * retention),
		delta = max(-followers, floor((viral - 0.5) * 30 * (1 + followers / 300) + 0.5)), cuts = cuts,
	}
	local L = {}
	local r3 = ret[4] or ret[#ret]
	if hs >= 0.85 then L[#L + 1] = "Hook: opened right on the build-up."
	elseif hs >= 0.5 then L[#L + 1] = "Hook: okay, but not the strongest frame."
	else L[#L + 1] = "Hook landed late, lost " .. floor((1 - r3) * 100 + 0.5) .. "% in 3s." end
	if dragSecs >= 2 then
		local third = clamp(floor((worstSec - 1) / (secs / 3)), 0, 2)
		L[#L + 1] = "Cuts dragged in the " .. ({ "first", "middle", "last" })[third + 1] .. " third."
	elseif jumpy >= 3 then L[#L + 1] = "Too jumpy: cuts came faster than the clip wanted."
	else L[#L + 1] = "Pacing held the audience." end
	if missed > 0 then L[#L + 1] = "Missed " .. missed .. " of " .. #c.markers .. " big moments. Cut on the action." end
	if #cuts == 0 then L[#L + 1] = "No cuts at all!"
	elseif syncD < 1.5 then L[#L + 1] = "Tight beat sync. Cuts hit the beat."
	else L[#L + 1] = "Cuts drifted " .. string.format("%.1f", syncD) .. " frames off the beat." end
	L[#L + 1] = capNote
	L[#L + 1] = trendLine
	res.lines = L
	return res
end

---------------------------------------------------------------- game state
local G = { mode = "title", followers = 0, week = 1, vid = 1, weekStart = 0, trend = TRENDS[1],
	prevTrend = nil, sandbox = false, sandType = 1, menu = 1, bestViral = 0 }
local clip, ed, res
local ph, prevF = 0, 0
local budget, budgetMax = 1, 1
local flash = 0
local sel = 1
local playing = false
local cap = { step = 1, opt = 1 }
local pub = {}
local toast, toastT = nil, 0
local frameN = 0

local WEEK_NAMES = { "Intern Week", "Side Hustle", "Rising Creator", "Brand Deal", "Viral Season", "Own Channel" }
local function unlocked(week)
	local n = clamp(2 + (week - 1) * 1, 2, 6)
	if week == 2 then n = 4 elseif week == 3 then n = 5 elseif week >= 4 then n = 6 end
	local t = {}
	for i = 1, n do t[i] = TYPE_ORDER[i] end
	return t
end
local function weekTarget(week) return 20 + 15 * (week - 1) end

local function save()
	pd.datastore.write({ followers = G.followers, week = G.week, best = G.bestViral })
end
local function load()
	local d = pd.datastore.read()
	if d then
		G.followers = d.followers or 0
		G.week = d.week or 1
		G.bestViral = d.best or 0
	end
end

local function say(s) toast, toastT = s, 60 end

local function pickTrend()
	G.prevTrend = G.trend
	G.trend = TRENDS[random(#TRENDS)]
end

local function startWeek()
	G.vid = 1
	G.weekStart = G.followers
	pickTrend()
end

local function beginVideo(typeId)
	clip = newClip(typeId)
	ed = { cuts = {}, hook = nil }
	ph, prevF, flash, sel, playing = 0, 0, 0, 1, false
	budgetMax = G.sandbox and 1 or max(5500, 9000 - 400 * (G.week - 1))
	budget = budgetMax
	G.mode = "intro"
end

local function startCareerVideo()
	local ul = unlocked(G.week)
	beginVideo(ul[random(#ul)])
end

local function enterPass(m)
	G.mode = m
	ph = 0; flash = 0; playing = false
	if m == "beat" then
		sel = 1
		if #ed.cuts > 0 then ph = ed.cuts[1] end
	elseif m == "caption" then
		cap = { step = 1, opt = 1 }
	end
	prevF = floor(ph + 0.5)
end

local function startPublish()
	local stale = (not G.sandbox) and G.prevTrend and G.prevTrend.id == G.trend.id
	res = evaluate(clip, ed, G.trend, stale, G.followers)
	pub = { stage = "teaser", t = 0, ph = 0, prev = 0, countT = 0 }
	G.mode = "publish"
	note(sLead, 440, 0.1, 0.5)
end

---------------------------------------------------------------- input
local hold = { l = 0, r = 0, u = 0, d = 0 }
local inp = {}
local function rep(btn, k)
	if pd.buttonIsPressed(btn) then
		hold[k] = hold[k] + 1
		local h = hold[k]
		return h == 1 or (h > 10 and h % 2 == 0)
	end
	hold[k] = 0
	return false
end
local function readInput()
	inp.a = pd.buttonJustPressed(pd.kButtonA)
	inp.b = pd.buttonJustPressed(pd.kButtonB)
	inp.l = rep(pd.kButtonLeft, "l")
	inp.r = rep(pd.kButtonRight, "r")
	inp.u = rep(pd.kButtonUp, "u")
	inp.d = rep(pd.kButtonDown, "d")
	inp.step = (inp.r and 1 or 0) - (inp.l and 1 or 0)
	inp.crank = pd.getCrankChange()
end

local function fnow() return clamp(floor(ph + 0.5), 0, clip.len - 1) end

-- scrub the playhead with the crank (+ d-pad single frame steps); drains budget
local function scrub(costScale)
	local before = fnow()
	local move = inp.crank / GEAR + inp.step
	ph = clamp(ph + move, 0, clip.len - 1)
	local f = fnow()
	if not G.sandbox then
		budget = budget - (abs(inp.crank) + abs(inp.step) * GEAR) * (costScale or 1)
	end
	if f ~= before then
		if f % 4 == 0 then note(sTick, 1100, 0.01, 0.25) end
		if floor(f / clip.beat) ~= floor(before / clip.beat) then note(sHat, 3000, 0.02, 0.3) end
	end
end

local function outOfTime()
	if not G.sandbox and budget <= 0 then
		say("OUT OF SCRUB TIME!")
		after(1, startPublish)
		budget = 1e-3
		G.mode = "wait"
		return true
	end
	return false
end

---------------------------------------------------------------- drawing: editor
local function drawPreviewFrame(f)
	gfx.setDrawOffset(PX, PY)
	gfx.setColor(WHITE)
	gfx.fillRect(0, 0, PW, PH)
	clip.draw(clip, f)
	gfx.setDrawOffset(0, 0)
	-- mask anything that spilled outside the preview window
	gfx.setColor(WHITE)
	gfx.fillRect(0, 0, 400, PY)
	gfx.fillRect(0, PY, PX, PH)
	gfx.fillRect(PX + PW, PY, 400 - PX - PW, PH)
	gfx.fillRect(0, PY + PH, 400, 240 - PY - PH)
	gfx.setColor(BLACK)
	gfx.drawRect(PX - 1, PY - 1, PW + 2, PH + 2)
	if flash > 0 then
		gfx.setColor(gfx.kColorXOR)
		gfx.fillRect(PX, PY, PW, PH)
		gfx.setColor(BLACK)
		flash = flash - 1
	end
end

local function drawCaptionText(s)
	local w = gfx.getTextSize(s)
	local x = PX + PW / 2 - w / 2 - 6
	gfx.setColor(WHITE); gfx.fillRect(x, PY + PH - 26, w + 12, 20)
	gfx.setColor(BLACK); gfx.drawRect(x, PY + PH - 26, w + 12, 20)
	txt(s, x + 6, PY + PH - 24)
end

local function fx(f, x0, w) return x0 + f / clip.len * w end

local function drawTimeline(y, h, waveform)
	local x0, w = 6, 388
	gfx.setColor(WHITE); gfx.fillRect(x0, y, w, h)
	gfx.setColor(BLACK); gfx.drawRect(x0, y, w, h)
	if waveform then
		for x = 0, w - 2, 2 do
			local f = x / w * clip.len
			local phase = (f % clip.beat) / clip.beat
			local amp = 0.12 + 0.8 * exp(-phase * 7)
			local hh = amp * (h - 8) / 2
			gfx.drawLine(x0 + 1 + x, y + h / 2 - hh, x0 + 1 + x, y + h / 2 + hh)
		end
	else
		for b = 0, clip.len, clip.beat do
			local x = fx(b, x0, w)
			gfx.drawLine(x, y + h - 4, x, y + h - 1)
		end
	end
	-- caption bar
	if ed.capS and ed.capE then
		gfx.setColor(BLACK)
		gfx.fillRect(fx(ed.capS, x0, w), y + h - 7, max(2, fx(ed.capE, x0, w) - fx(ed.capS, x0, w)), 4)
	end
	-- cuts
	for i, f in ipairs(ed.cuts) do
		local x = fx(f, x0, w)
		gfx.setColor(BLACK)
		if waveform and G.mode == "beat" and i == sel then
			gfx.setLineWidth(3); gfx.drawLine(x, y - 2, x, y + h + 2); gfx.setLineWidth(1)
		else
			gfx.drawLine(x, y, x, y + h)
		end
		gfx.fillTriangle(x - 3, y - 4, x + 3, y - 4, x, y)
	end
	if ed.hook then
		local x = fx(ed.hook, x0, w)
		gfx.setColor(BLACK); gfx.fillRect(x - 1, y - 8, 11, 8)
		whiteText(function() txt("H", x + 1, y - 10) end)
	end
	-- playhead
	local px = fx(ph, x0, w)
	gfx.setColor(BLACK)
	gfx.setLineWidth(2); gfx.drawLine(px, y - 2, px, y + h + 2); gfx.setLineWidth(1)
	gfx.fillTriangle(px - 4, y + h + 6, px + 4, y + h + 6, px, y + h + 1)
end

local function drawJog(cx, cy, f)
	gfx.setColor(BLACK)
	gfx.drawCircleAtPoint(cx, cy, 28)
	gfx.drawCircleAtPoint(cx, cy, 10)
	local a0 = pd.getCrankPosition() * pi / 180
	for i = 0, 11 do
		local a = a0 + i * pi / 6
		line(cx + cos(a) * 20, cy + sin(a) * 20, cx + cos(a) * 28, cy + sin(a) * 28, i == 0 and 3 or 1)
	end
	txtC("F" .. f, cx, cy - 8)
end

local function drawBar(x, y, w, h, v)
	gfx.setColor(WHITE); gfx.fillRect(x, y, w, h)
	gfx.setColor(BLACK); gfx.drawRect(x, y, w, h)
	gfx.fillRect(x + 1, y + 1, (w - 2) * clamp(v, 0, 1), h - 2)
end

local PASS_NAMES = { hook = "1 HOOK", cuts = "2 CUTS", beat = "3 BEAT", caption = "4 CAPTION" }
local FOOTER = {
	hook = "CRANK: scrub   A: open on this frame",
	cuts = "CRANK: scrub  A: cut/uncut  B: next pass",
	beat = "<>:pick  ^:snap  CRANK:nudge  A:play  B:next",
	caption = "",
}

local function drawEditor(f)
	drawPreviewFrame(f)
	-- header
	gfx.setColor(BLACK); gfx.fillRect(0, 0, 400, 17)
	whiteText(function()
		txt("CRANK CUT", 6, 1)
		txtC(PASS_NAMES[G.mode] or "", 200, 1)
		txtR(clip.name, 394, 1)
	end)
	-- right panel
	txt("SCRUB TIME", 276, 20)
	if G.sandbox then txt("unlimited", 276, 36) else drawBar(276, 38, 118, 9, budget / budgetMax) end
	drawJog(335, 80, f)
	if pd.isCrankDocked() then
		txtC("undock crank", 335, 110)
	else
		txtC(string.format("%.2fs", f / 30), 335, 110)
	end
end

local function drawFooter(s)
	gfx.setColor(BLACK); gfx.fillRect(0, 222, 400, 18)
	whiteText(function() txtC(s, 200, 223) end)
end

---------------------------------------------------------------- passes
local function updateHook()
	scrub(1)
	if outOfTime() then return end
	local f = fnow()
	if inp.a then
		ed.hook = f
		note(sChunk, 200, 0.08, 0.7)
		say("HOOK SET")
		enterPass("cuts")
		return
	end
	drawEditor(f)
	local hs = hookScore(clip, f)
	txt("AUDIENCE", 276, 126)
	drawBar(276, 142, 118, 9, hs)
	local msg = hs >= 0.85 and "HOOKED!" or (hs >= 0.5 and "Interested" or "Swiping...")
	txtC(msg, 335, 154)
	drawTimeline(176, 30, false)
	drawFooter(FOOTER.hook)
end

local function updateCuts()
	scrub(1)
	if outOfTime() then return end
	local f = fnow()
	if inp.a then
		local removed = false
		for i, cf in ipairs(ed.cuts) do
			if abs(cf - f) <= 3 then table.remove(ed.cuts, i); removed = true; break end
		end
		if not removed then
			ed.cuts[#ed.cuts + 1] = f
			table.sort(ed.cuts)
			note(sChunk, 300, 0.09, 0.9)
			note(sKick, 90, 0.1, 0.8)
		else
			note(sTick, 500, 0.04, 0.4)
		end
		flash = 3
	end
	if inp.b then
		enterPass(#ed.cuts > 0 and "beat" or "caption")
		return
	end
	drawEditor(f)
	local last = 0
	for _, cf in ipairs(ed.cuts) do if cf <= f then last = max(last, cf) end end
	local pace = (f - last) / (clip.T * 1.6)
	txt("PACE", 276, 126)
	drawBar(276, 142, 118, 9, pace)
	txtC(pace > 0.9 and "DRAGGING!" or ("cuts: " .. #ed.cuts), 335, 154)
	drawTimeline(176, 30, false)
	drawFooter(FOOTER.cuts)
end

local function updateBeat()
	local f
	if playing then
		local prev = floor(ph)
		ph = ph + 1
		if ph >= clip.len - 1 then ph = clip.len - 1; playing = false end
		f = fnow()
		for g = prev + 1, floor(ph) do
			if g % clip.beat == 0 then note(sKick, 70, 0.1, 0.8) end
			for _, cf in ipairs(ed.cuts) do if cf == g then note(sChunk, 300, 0.07, 0.6); flash = 2 end end
		end
		if inp.a then playing = false end
	else
		if inp.l then sel = max(1, sel - 1) end
		if inp.r then sel = min(#ed.cuts, sel + 1) end
		if inp.l or inp.r then ph = ed.cuts[sel] end
		local c = ed.cuts[sel]
		if inp.u then
			local r = c % clip.beat
			c = (r < clip.beat / 2) and (c - r) or (c - r + clip.beat)
			note(sTick, 1600, 0.03, 0.5)
		end
		local nudge = inp.crank / 6
		if nudge ~= 0 then
			cap.acc = (cap.acc or 0) + nudge
			local whole = (cap.acc >= 0) and floor(cap.acc) or ceil(cap.acc)
			if whole ~= 0 then
				cap.acc = cap.acc - whole
				c = c + whole
				if not G.sandbox then budget = budget - abs(inp.crank) * 0.3 end
				note(sTick, 1000, 0.01, 0.2)
			end
		end
		local lo = (sel > 1) and ed.cuts[sel - 1] + 2 or 1
		local hi = (sel < #ed.cuts) and ed.cuts[sel + 1] - 2 or clip.len - 2
		c = clamp(c, lo, hi)
		if c ~= ed.cuts[sel] then
			ed.cuts[sel] = c
			if beatDist(clip, c) == 0 then note(sKick, 70, 0.08, 0.7); flash = 2 end
		end
		ph = ed.cuts[sel]
		f = fnow()
		if inp.a then playing = true; ph = max(0, ed.cuts[sel] - 30); f = fnow() end
		if not G.sandbox and budget <= 0 then outOfTime(); return end
		if inp.b then enterPass("caption"); return end
	end
	drawEditor(f)
	local c = ed.cuts[sel]
	local off = c % clip.beat
	if off > clip.beat / 2 then off = off - clip.beat end
	txt("CUT " .. sel .. "/" .. #ed.cuts, 276, 126)
	drawBar(276, 142, 118, 9, 1 - abs(off) / (clip.beat / 2))
	txtC(off == 0 and "ON BEAT!" or string.format("%+d frames", -off), 335, 154)
	drawTimeline(180, 34, true)
	drawFooter(playing and "A: stop preview" or FOOTER.beat)
end

local function updateCaption()
	if cap.step == 1 then
		if inp.u then cap.opt = max(1, cap.opt - 1) end
		if inp.d then cap.opt = min(#clip.caps, cap.opt + 1) end
		if inp.a then
			cap.step = 2; ed.capText = cap.opt; ph = 0
			note(sChunk, 300, 0.08, 0.7)
		end
		if inp.b then
			ed.capText = nil
			after(1, startPublish); G.mode = "wait"; return
		end
		drawEditor(fnow())
		gfx.setColor(WHITE); gfx.fillRect(0, 158, 400, 64)
		gfx.setColor(BLACK); gfx.drawRect(6, 159, 388, 61)
		txt("Pick a caption:", 14, 160)
		for i, cp in ipairs(clip.caps) do
			txt((i == cap.opt and "> " or "   ") .. cp[1], 20, 160 + i * 14)
		end
		drawFooter("UP/DOWN: choose   A: confirm   B: no caption")
		return
	end
	scrub(1)
	if outOfTime() then return end
	local f = fnow()
	if cap.step == 2 then
		ed.capS, ed.capE = nil, nil
		if inp.a then
			cap.s = f; cap.step = 3
			ed.capS, ed.capE = f, f + 10
			note(sChunk, 300, 0.08, 0.7)
		end
	else
		ed.capS = cap.s
		ed.capE = max(f, cap.s + 10)
		if inp.a then
			ph = ed.capE
			note(sChunk, 200, 0.12, 0.9)
			after(1, startPublish); G.mode = "wait"
			return
		end
	end
	if inp.b then
		cap.step = max(2, cap.step - 1)
		if cap.step == 2 then ed.capS, ed.capE = nil, nil end
	end
	drawEditor(f)
	local show = ed.capS and (f >= ed.capS and f <= ed.capE)
	if cap.step == 2 or show then drawCaptionText(clip.caps[ed.capText][1]) end
	txt("CAPTION", 276, 126)
	txtC(cap.step == 2 and "set START" or "set END", 335, 144)
	txtC(cap.step == 3 and string.format("%.1fs on", (ed.capE - ed.capS) / 30) or "", 335, 158)
	drawTimeline(176, 30, false)
	drawFooter(cap.step == 2 and "CRANK to start frame, A: set" or "CRANK to end frame, A: publish  B: back")
end

---------------------------------------------------------------- publish
local function drawRetentionGraph(y, h, upTo)
	local x0, w = 6, 388
	gfx.setColor(WHITE); gfx.fillRect(x0, y, w, h)
	gfx.setColor(BLACK); gfx.drawRect(x0, y, w, h)
	local arr = res.retArr
	local n = #arr - 1
	local lastx, lasty
	for i = 0, n do
		local f = min(i * 30, clip.len)
		if f > upTo then break end
		local x = x0 + f / clip.len * w
		local yy = y + h - 2 - arr[i + 1] * (h - 4)
		if lastx then gfx.drawLine(lastx, lasty, x, yy) end
		lastx, lasty = x, yy
	end
	txt("AUDIENCE", 10, y - 16)
end

local function updatePublish()
	frameN = frameN + 1
	pub.t = pub.t + 1
	if pub.stage == "teaser" then
		local f = ed.hook or 0
		drawPreviewFrame(f)
		gfx.setColor(BLACK); gfx.fillRect(0, 0, 400, 17)
		whiteText(function() txtC("PUBLISHING...", 200, 1) end)
		drawRetentionGraph(176, 40, 0)
		bigText("HOOK", 335, 70, 2, "c")
		if pub.t > 40 or inp.a then pub.stage = "play"; pub.t = 0; pub.ph = 0; pub.prev = 0 end
	elseif pub.stage == "play" then
		pub.prev = pub.ph
		pub.ph = pub.ph + 2
		if pub.ph >= clip.len then pub.ph = clip.len - 1 end
		local f = floor(pub.ph)
		for g = floor(pub.prev) + 1, f do
			if g % clip.beat == 0 then note(sKick, 70, 0.1, 0.6) end
			for _, cf in ipairs(res.cuts) do if cf == g then flash = 2; note(sChunk, 300, 0.06, 0.4) end end
		end
		drawPreviewFrame(f)
		if ed.capText and ed.capS and f >= ed.capS and f <= ed.capE then drawCaptionText(clip.caps[ed.capText][1]) end
		gfx.setColor(BLACK); gfx.fillRect(0, 0, 400, 17)
		whiteText(function() txtC("PUBLISHING...", 200, 1) end)
		drawRetentionGraph(176, 40, f)
		local px = 6 + f / clip.len * 388
		gfx.drawLine(px, 176, px, 216)
		local cur = res.retArr[min(#res.retArr, floor(f / 30) + 1)]
		bigText(floor(cur * 100) .. "%", 335, 70, 2, "c")
		txtC("watching", 335, 108)
		if pub.ph >= clip.len - 1 or inp.a then pub.stage = "count"; pub.t = 0 end
	elseif pub.stage == "count" then
		gfx.clear(WHITE)
		local e = clamp(pub.t / 70, 0, 1)
		e = 1 - (1 - e) ^ 3
		if pub.t < 70 and pub.t % 3 == 0 then note(sTick, 300 + pub.t * 12, 0.03, 0.4) end
		if pub.t == 70 then
			if res.viral >= 1 then fanfare() else sadTrombone() end
		end
		gfx.setColor(BLACK); gfx.fillRect(0, 0, 400, 22)
		whiteText(function() txtC("PUBLISHED!", 200, 3) end)
		txt("VIEWS", 20, 40);         bigText(tostring(floor(res.views * e)), 20, 54, 2)
		txt("WATCH-THROUGH", 20, 100); bigText(floor(res.ret * 100 * e) .. "%", 20, 114, 2)
		txt("LIKES", 20, 160);        bigText(tostring(floor(res.likes * e)), 20, 174, 2)
		txt("SHARES", 150, 160);      bigText(tostring(floor(res.shares * e)), 150, 174, 2)
		txt("VIRAL SCORE", 230, 40);  bigText(tostring(floor(res.viral * 100 * e)), 230, 60, 4)
		if pub.t > 70 then txtC("A: verdict", 200, 218) end
		if pub.t > 70 and inp.a then
			pub.stage = "verdict"; pub.t = 0
			if not G.sandbox then
				G.followers = max(0, G.followers + res.delta)
				G.bestViral = max(G.bestViral, floor(res.viral * 100))
				save()
			end
		end
	elseif pub.stage == "verdict" then
		gfx.clear(WHITE)
		local slide = clamp(1 - pub.t / 14, 0, 1)
		local oy = floor(slide * 240)
		gfx.setDrawOffset(0, oy)
		gfx.setColor(BLACK); gfx.fillRect(0, 0, 400, 22)
		whiteText(function() txtC("VERDICT", 200, 3) end)
		gfx.drawRect(4, 28, 392, 150)
		for i, l in ipairs(res.lines) do txt(l, 12, 30 + (i - 1) * 24) end
		if G.sandbox then
			txtC("Sandbox: no followers at stake.", 200, 186)
		else
			local s = (res.delta >= 0 and "+" or "") .. res.delta
			txtC("Followers " .. s .. "  (now " .. G.followers .. ")", 200, 186)
		end
		gfx.setDrawOffset(0, 0)
		if pub.t > 14 then txtC("A: continue", 200, 218) end
		if pub.t > 14 and inp.a then
			if G.sandbox then
				G.mode = "title"
			else
				G.vid = G.vid + 1
				if G.vid > 3 then G.mode = "weekend" else startCareerVideo() end
			end
		end
	end
end

---------------------------------------------------------------- menus
local function drawWheelLogo(cx, cy, r)
	gfx.setColor(BLACK)
	gfx.drawCircleAtPoint(cx, cy, r)
	gfx.drawCircleAtPoint(cx, cy, r - 6)
	local a0 = frameN * 0.05
	for i = 0, 11 do
		local a = a0 + i * pi / 6
		line(cx + cos(a) * (r - 6), cy + sin(a) * (r - 6), cx + cos(a) * r, cy + sin(a) * r, i == 0 and 3 or 1)
	end
	circ(cx, cy, 6)
end

local function updateTitle()
	frameN = frameN + 1
	if inp.u then G.menu = max(1, G.menu - 1) end
	if inp.d then G.menu = min(3, G.menu + 1) end
	if G.menu == 2 then
		if inp.l then G.sandType = (G.sandType - 2) % #TYPE_ORDER + 1 end
		if inp.r then G.sandType = G.sandType % #TYPE_ORDER + 1 end
	end
	if inp.a then
		if G.menu == 1 then
			G.sandbox = false
			startWeek()
			G.mode = "weekintro"
		elseif G.menu == 2 then
			G.sandbox = true
			beginVideo(TYPE_ORDER[G.sandType])
		else
			G.followers, G.week, G.bestViral = 0, 1, 0
			save()
			say("Career reset")
		end
	end
	gfx.clear(WHITE)
	drawWheelLogo(330, 80, 44)
	bigText("CRANK", 20, 6, 3)
	bigText("CUT", 20, 54, 3)
	txt("Edit the cut. Land the hook. Go viral.", 20, 116)
	local items = {
		"Career  (Week " .. G.week .. ", " .. G.followers .. " followers)",
		"Sandbox  < " .. TYPES[TYPE_ORDER[G.sandType]].name .. " >",
		"Reset career",
	}
	for i, s in ipairs(items) do txt((i == G.menu and "> " or "   ") .. s, 20, 140 + (i - 1) * 20) end
	if G.bestViral > 0 then txtR("Best viral: " .. G.bestViral, 394, 222) end
end

local function updateWeekIntro()
	if inp.a then startCareerVideo() end
	gfx.clear(WHITE)
	gfx.setColor(BLACK); gfx.fillRect(0, 0, 400, 22)
	whiteText(function() txtC("WEEK " .. G.week .. ": " .. (WEEK_NAMES[min(G.week, #WEEK_NAMES)]), 200, 3) end)
	txt("3 videos this week.", 20, 40)
	txt("Target: +" .. weekTarget(G.week) .. " followers", 20, 62)
	txt("Trend: " .. G.trend.name, 20, 90)
	txt(G.trend.desc, 20, 108)
	if G.prevTrend and G.prevTrend.id == G.trend.id then txt("(same as last week: stale!)", 20, 128) end
	txt("Footage this week:", 20, 150)
	local names = {}
	for _, id in ipairs(unlocked(G.week)) do names[#names + 1] = TYPES[id].name end
	gfx.drawTextInRect(table.concat(names, ", "), 20, 168, 360, 40)
	txtC("A: start", 200, 218)
end

local function updateIntro()
	if inp.a then enterPass("hook") end
	gfx.clear(WHITE)
	gfx.setColor(BLACK); gfx.fillRect(0, 0, 400, 22)
	whiteText(function()
		txtC(G.sandbox and "SANDBOX" or ("WEEK " .. G.week .. "  VIDEO " .. G.vid .. "/3"), 200, 3)
	end)
	bigText(clip.name, 200, 40, 2, "c")
	if not G.sandbox then
		txtC("Trend: " .. G.trend.name .. ". " .. G.trend.desc, 200, 100)
		txtC("Followers: " .. G.followers .. "   (week " .. (G.followers - G.weekStart) .. "/" .. weekTarget(G.week) .. ")", 200, 124)
	end
	txtC("Hook > Cuts > Beat > Caption > Publish", 200, 154)
	txtC("Crank scrubs. Cut on the action. Mind the clock.", 200, 174)
	txtC("A: start editing", 200, 218)
end

local function updateWeekEnd()
	local gain = G.followers - G.weekStart
	local target = weekTarget(G.week)
	local pass = gain >= target
	if inp.a then
		if pass then G.week = G.week + 1 end
		save()
		startWeek()
		G.mode = "weekintro"
	end
	gfx.clear(WHITE)
	gfx.setColor(BLACK); gfx.fillRect(0, 0, 400, 22)
	whiteText(function() txtC("WEEK " .. G.week .. " REVIEW", 200, 3) end)
	bigText("+" .. gain, 200, 40, 3, "c")
	txtC("followers this week (target +" .. target .. ")", 200, 90)
	if pass then
		bigText("PROMOTED!", 200, 116, 2, "c")
		if G.week + 1 >= 2 and G.week + 1 <= 4 then txtC("New footage type unlocked.", 200, 160) end
	else
		bigText("MISSED IT", 200, 116, 2, "c")
		txtC("Same week again. Learn from the verdicts.", 200, 160)
	end
	txtC("A: continue", 200, 218)
end

---------------------------------------------------------------- main
local dispatch = {
	title = updateTitle, weekintro = updateWeekIntro, intro = updateIntro, hook = updateHook,
	cuts = updateCuts, beat = updateBeat, caption = updateCaption, publish = updatePublish,
	weekend = updateWeekEnd, wait = function() end,
}

function pd.update()
	readInput()
	runLater()
	local fn = dispatch[G.mode]
	if fn then fn() end
	if toastT > 0 then
		toastT = toastT - 1
		local w = gfx.getTextSize(toast)
		gfx.setColor(BLACK); gfx.fillRect(200 - w / 2 - 8, 100, w + 16, 24)
		whiteText(function() txtC(toast, 200, 104) end)
	end
end

function pd.gameWillTerminate() save() end
function pd.gameWillSleep() save() end

load()
pd.getSystemMenu():addMenuItem("Main menu", function() G.mode = "title" end)
