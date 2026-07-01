local interpolation = {}

interpolation.lerp = function(a, b, t)
	return a + (b - a) * t
end

-- Linear interpolation on a Vector3-as-array {x, y, z}.
interpolation.lerp_v3 = function(a, b, t)
	return {
		a[1] + (b[1] - a[1]) * t,
		a[2] + (b[2] - a[2]) * t,
		a[3] + (b[3] - a[3]) * t,
	}
end

-- Angle lerp that takes the shorter arc.
interpolation.lerp_yaw = function(a, b, t)
	local diff = b - a
	-- Wrap diff into [-pi, pi]
	local PI = math.pi
	while diff > PI do diff = diff - 2 * PI end
	while diff < -PI do diff = diff + 2 * PI end
	return a + diff * t
end

-- Given sorted frames and elapsed time, return interpolated state.
-- Caller maintains an `idx` pointer for amortized O(1) advancement.
-- Returns: interpolated_frame, new_idx, finished
--
-- NOTE: `elapsed` must be monotonically non-decreasing across calls. Passing
-- a smaller `elapsed` than a previous call leaves `idx` stale and returns
-- interpolation between the wrong frames. Callers that need to scrub
-- backwards must reset by passing `idx = 1`.
interpolation.frame_at = function(frames, idx, elapsed)
	local n = #frames
	if n == 0 then return nil, idx, true end
	if elapsed <= frames[1].t then
		return frames[1], 1, false
	end
	-- Advance idx until frames[idx+1].t > elapsed
	while idx + 1 <= n and frames[idx + 1].t <= elapsed do
		idx = idx + 1
	end
	if idx >= n then
		return frames[n], n, true
	end
	local a = frames[idx]
	local b = frames[idx + 1]
	local span = b.t - a.t
	local alpha = span > 0 and (elapsed - a.t) / span or 0
	local interp = {
		t  = elapsed,
		p  = interpolation.lerp_v3(a.p, b.p, alpha),
		y  = interpolation.lerp_yaw(a.y, b.y, alpha),
		hp = interpolation.lerp(a.hp or 0, b.hp or 0, alpha),
		to = interpolation.lerp(a.to or 0, b.to or 0, alpha),
		ab = interpolation.lerp(a.ab or 0, b.ab or 0, alpha),
		w  = a.w,                                  -- step function (rarely changes)
		st = a.st or "walking",                    -- step function (replaces v0 `d`)
		pg = (a.pg and b.pg) and interpolation.lerp(a.pg, b.pg, alpha) or a.pg,
	}
	return interp, idx, false
end

return interpolation
