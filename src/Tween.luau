local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Interpolate = require(script.Parent.Interpolate)
local State = require(script.Parent.State)
local Type = require(script.Parent.Type)

local Tween = {}
Tween.__index = Tween

local tweens = setmetatable({}, { __mode = "_k" })
Tween._tweens = tweens

function Tween.new<T>(state: T | Type.Function | State.State<T>, tweenInfo: State.Stateful<TweenInfo>): State.State<T>
	if type(state) == "function" then
		state = State.compute(state)
	elseif State.isState(state) and (state :: any)._computation == nil then
		-- TODO: find a better way to update this state without a new closure
		state = State.compute(function()
			return (state :: any)()
		end)
	else
		state = State.new(state)
	end

	local self = state :: State.State<T>
	self._tweenInfo = tweenInfo
	self._tweenStart = self._value
	Tween._tweens[self] = true

	return self
end

RunService.Heartbeat:Connect(function()
	for tween in tweens do
		if tween._tweenInit then
			local now = os.clock()
			local delta = now - tween._tweenInit
			if delta < 0 then
				continue -- skip until DelayTime
			end

			local info = State.raw(tween._tweenInfo)
			local alpha = delta / info.Time

			if alpha < (if info.Reverses then 2 else 1) then
				if info.Reverses then
					alpha = 1 - (alpha - 1)
				end
				local t = TweenService:GetValue(alpha, info.EasingStyle, info.EasingDirection)
				tween._value = Interpolate(tween._tweenStart, tween._tweenGoal, t)
			else
				if (tween._tweenRepeat or 0) > 0 then
					tween._tweenRepeat -= 1
					tween._tweenInit = now + info.DelayTime
				else -- finish
					tween._tweenInit = nil
				end
				tween._value = if info.Reverses then tween._tweenStart else tween._tweenGoal
			end
			task.spawn(tween._update, tween, true, true, true)
		end
	end
end)

return Tween
