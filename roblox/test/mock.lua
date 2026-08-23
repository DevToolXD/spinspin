--=====================================================================
-- Roblox API 모의 구현 (테스트 전용)
--=====================================================================

function approx(a, b, eps)
	return math.abs(a - b) <= (eps or 1e-4)
end

------------------------------------------------------------- Vector3
local v3methods = {}
local v3mt
v3mt = {
	__index = function(self, key)
		if key == "Magnitude" then
			return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
		elseif key == "Unit" then
			local m = math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
			return Vector3.new(self.X / m, self.Y / m, self.Z / m)
		end
		return v3methods[key]
	end,
	__add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end,
	__sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end,
	__unm = function(a) return Vector3.new(-a.X, -a.Y, -a.Z) end,
	__mul = function(a, b)
		if type(b) == "number" then return Vector3.new(a.X * b, a.Y * b, a.Z * b) end
		if type(a) == "number" then return Vector3.new(b.X * a, b.Y * a, b.Z * a) end
		return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
	end,
	__tostring = function(v) return string.format("(%.2f, %.2f, %.2f)", v.X, v.Y, v.Z) end,
}
Vector3 = {}
function Vector3.new(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, v3mt)
end
function v3methods:Cross(o)
	return Vector3.new(
		self.Y * o.Z - self.Z * o.Y,
		self.Z * o.X - self.X * o.Z,
		self.X * o.Y - self.Y * o.X
	)
end
function v3methods:Dot(o) return self.X * o.X + self.Y * o.Y + self.Z * o.Z end

Vector2 = {}
local v2mt = {
	__sub = function(a, b) return Vector2.new(a.X - b.X, a.Y - b.Y) end,
	__add = function(a, b) return Vector2.new(a.X + b.X, a.Y + b.Y) end,
}
function Vector2.new(x, y) return setmetatable({ X = x or 0, Y = y or 0 }, v2mt) end

-------------------------------------------------------------- CFrame
-- 회전은 행 우선 9개 배열: r[1]=R00 r[2]=R01 r[3]=R02 r[4]=R10 ... r[9]=R22
-- Roblox 규약: RightVector=1열, UpVector=2열, LookVector=-(3열)
local cfmethods = {}
local cfmt
cfmt = {
	__index = function(self, key)
		if key == "Position" or key == "p" then
			return Vector3.new(self.x, self.y, self.z)
		elseif key == "Rotation" then
			return CFrame._make(0, 0, 0, self.r)
		elseif key == "LookVector" then
			return Vector3.new(-self.r[3], -self.r[6], -self.r[9])
		elseif key == "RightVector" then
			return Vector3.new(self.r[1], self.r[4], self.r[7])
		elseif key == "UpVector" then
			return Vector3.new(self.r[2], self.r[5], self.r[8])
		end
		return cfmethods[key]
	end,
	__mul = function(a, b)
		-- a * b (둘 다 CFrame)
		local ar, br = a.r, b.r
		local nr = {}
		for row = 0, 2 do
			for col = 0, 2 do
				local sum = 0
				for k = 0, 2 do
					sum = sum + ar[row * 3 + k + 1] * br[k * 3 + col + 1]
				end
				nr[row * 3 + col + 1] = sum
			end
		end
		local bp = b.Position
		local wx = ar[1] * bp.X + ar[2] * bp.Y + ar[3] * bp.Z
		local wy = ar[4] * bp.X + ar[5] * bp.Y + ar[6] * bp.Z
		local wz = ar[7] * bp.X + ar[8] * bp.Y + ar[9] * bp.Z
		return CFrame._make(a.x + wx, a.y + wy, a.z + wz, nr)
	end,
	__tostring = function(c)
		local l = c.LookVector
		return string.format("pos(%.2f,%.2f,%.2f) look(%.3f,%.3f,%.3f)", c.x, c.y, c.z, l.X, l.Y, l.Z)
	end,
}

CFrame = {}
function CFrame._make(x, y, z, r)
	return setmetatable({ x = x, y = y, z = z, r = { r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9] } }, cfmt)
end

local IDENTITY_R = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }

function CFrame.new(a, b, c)
	if type(a) == "table" then
		return CFrame._make(a.X, a.Y, a.Z, IDENTITY_R)
	end
	return CFrame._make(a or 0, b or 0, c or 0, IDENTITY_R)
end

-- 오른쪽/위/뒤 축으로 CFrame 구성 (뒤 = -앞)
function CFrame.fromAxes(pos, right, up, back)
	return CFrame._make(pos.X, pos.Y, pos.Z, {
		right.X, up.X, back.X,
		right.Y, up.Y, back.Y,
		right.Z, up.Z, back.Z,
	})
end

function CFrame.lookAt(from, to, up)
	up = up or Vector3.new(0, 1, 0)
	local forward = (to - from).Unit
	local right = forward:Cross(up).Unit
	local trueUp = right:Cross(forward)
	return CFrame.fromAxes(from, right, trueUp, -forward)
end

function cfmethods:Lerp(goal, t)
	if t >= 1 then return goal end
	if t <= 0 then return self end
	local p = self.Position + (goal.Position - self.Position) * t
	local f1, f2 = self.LookVector, goal.LookVector
	local u1, u2 = self.UpVector, goal.UpVector
	local f = (f1 + (f2 - f1) * t).Unit
	local u = u1 + (u2 - u1) * t
	local r = f:Cross(u).Unit
	return CFrame.fromAxes(p, r, r:Cross(f), -f)
end

------------------------------------------------------- UDim / Color3
UDim = {}
function UDim.new(s, o) return { Scale = s or 0, Offset = o or 0 } end
UDim2 = {}
function UDim2.new(xs, xo, ys, yo)
	return { X = UDim.new(xs, xo), Y = UDim.new(ys, yo) }
end
function UDim2.fromOffset(x, y) return UDim2.new(0, x, 0, y) end
Color3 = {}
function Color3.fromRGB(r, g, b) return { R = r / 255, G = g / 255, B = b / 255 } end

---------------------------------------------------------------- Enum
Enum = setmetatable({}, {
	__index = function(t, catName)
		local cat = setmetatable({}, {
			__index = function(c, itemName)
				local item = { Name = itemName, Value = 0, EnumType = catName }
				rawset(c, itemName, item)
				return item
			end,
		})
		rawset(t, catName, cat)
		return cat
	end,
})
-- 실제 숫자가 의미 있는 것만 진짜 값으로 고정
Enum.RenderPriority.First.Value = 0
Enum.RenderPriority.Input.Value = 100
Enum.RenderPriority.Camera.Value = 200
Enum.RenderPriority.Character.Value = 300
Enum.RenderPriority.Last.Value = 2000

-------------------------------------------------------------- Signal
function newSignal()
	local sig = { _handlers = {} }
	function sig:Connect(fn)
		table.insert(self._handlers, fn)
		return { Disconnect = function() end, Connected = true }
	end
	function sig:Fire(...)
		for _, fn in ipairs(self._handlers) do fn(...) end
	end
	return sig
end

------------------------------------------------------------ Instance
local instMethods = {}
local instMt = {
	__index = function(self, key)
		if key == "Parent" then return rawget(self, "_parent") end
		return instMethods[key]
	end,
	__newindex = function(self, key, value)
		if key == "Parent" then
			local old = rawget(self, "_parent")
			if old and rawget(old, "Children") then
				for i, child in ipairs(old.Children) do
					if child == self then table.remove(old.Children, i) break end
				end
			end
			rawset(self, "_parent", value)
			if value and rawget(value, "Children") then
				table.insert(value.Children, self)
			end
			return
		end
		rawset(self, key, value)
	end,
}
function instMethods:FindFirstChild(name)
	for _, child in ipairs(self.Children) do
		if child.Name == name then return child end
	end
	return nil
end
function instMethods:FindFirstChildOfClass(cls)
	for _, child in ipairs(self.Children) do
		if child.ClassName == cls then return child end
	end
	return nil
end
function instMethods:GetChildren() return self.Children end
function instMethods:WaitForChild(name, timeout)
	local found = self:FindFirstChild(name)
	if not found and not timeout then error("WaitForChild 실패: " .. tostring(name)) end
	return found
end
function instMethods:Destroy() self.Parent = nil end

Instance = {}
function Instance.new(className, parent)
	local obj = setmetatable({}, instMt)
	rawset(obj, "ClassName", className)
	rawset(obj, "Name", className)
	rawset(obj, "Children", {})
	rawset(obj, "_parent", nil)
	rawset(obj, "InputBegan", newSignal())
	rawset(obj, "InputChanged", newSignal())
	rawset(obj, "MouseButton1Click", newSignal())
	rawset(obj, "Changed", newSignal())
	rawset(obj, "CharacterAdded", newSignal())
	if parent then obj.Parent = parent end
	return obj
end

RaycastParams = {}
function RaycastParams.new()
	return { FilterDescendantsInstances = {}, FilterType = nil, IgnoreWater = false }
end

-- Roblox의 warn (luau CLI에는 없음)
WARNINGS = {}
function warn(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
	local msg = table.concat(parts, " ")
	table.insert(WARNINGS, msg)
	print("   [warn] " .. msg)
end

-- print를 가로채서 테스트가 로드 메시지를 확인할 수 있게
PRINTS = {}
local realPrint = print
function print(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
	table.insert(PRINTS, table.concat(parts, " "))
	realPrint(...)
end
