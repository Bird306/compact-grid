--!native
--!strict
--!optimize 2

export type Grid = {
	invCellSize: number,
	hashtableSize: number,
	n: number,
	cellStarts: buffer,
	cellEntries: buffer,
}

export type MultiQueryResult = {
	entries: { number },
	counts: { number },
}

local U32 = 4
local FANTASYX = 92837111
local FANTASYY = 689287499
local FANTASYZ = 283923481

local function posToCell(x: number, y: number, z: number, invCellSize: number): (number, number, number)
	return math.floor(x * invCellSize), math.floor(y * invCellSize), math.floor(z * invCellSize)
end

local function cellToHash(cx: number, cy: number, cz: number, hashtableSize: number): number
	local h = bit32.bxor(cx * FANTASYX, cy * FANTASYY, cz * FANTASYZ)
	return math.abs(h) % hashtableSize
end

local function posToHash(x: number, y: number, z: number, invCellSize: number, hashtableSize: number): number
	local cx, cy, cz = posToCell(x, y, z, invCellSize)
	return cellToHash(cx, cy, cz, hashtableSize)
end

local CompactGrid = {}

CompactGrid.new = function(cellSize: number, hashtableSize: number, reserved: number): Grid
	return {
		invCellSize = 1 / cellSize,
		hashtableSize = hashtableSize,
		n = 0,
		cellStarts = buffer.create(U32 * (hashtableSize + 1)),
		cellEntries = buffer.create(U32 * reserved),
	}
end

CompactGrid.update = function(grid: Grid, positions: { Vector3 })
	local invCellSize = grid.invCellSize
	local hashtableSize = grid.hashtableSize
	local cellStarts = grid.cellStarts
	local cellEntries = grid.cellEntries

	local n = #positions

	do
		local newNByte = n * U32
		if newNByte > buffer.len(cellEntries) then
			cellEntries = buffer.create(newNByte)
			grid.cellEntries = cellEntries
		end
		grid.n = n
	end

	buffer.fill(cellStarts, 0, 0)

	for _, pos in positions do
		local h = posToHash(pos.X, pos.Y, pos.Z, invCellSize, hashtableSize) * U32
		buffer.writeu32(cellStarts, h, buffer.readu32(cellStarts, h) + 1)
	end

	local start = 0
	for i = 0, (hashtableSize - 1) * U32, U32 do
		start += buffer.readu32(cellStarts, i)
		buffer.writeu32(cellStarts, i, start)
	end
	buffer.writeu32(cellStarts, hashtableSize * U32, start)

	for i = 1, n do
		local pos = positions[i]
		local h = posToHash(pos.X, pos.Y, pos.Z, invCellSize, hashtableSize) * U32
		local writePos = buffer.readu32(cellStarts, h) - 1
		buffer.writeu32(cellEntries, writePos * U32, i)
		buffer.writeu32(cellStarts, h, writePos)
	end
end

CompactGrid.queryRegion = function(grid: Grid, origin: Vector3, halfExtent: Vector3, queryResults: { number }): number
	local invCellSize = grid.invCellSize
	local hashtableSize = grid.hashtableSize
	local cellStarts = grid.cellStarts
	local cellEntries = grid.cellEntries

	local resultCount = 0

	local min = origin - halfExtent
	local max = origin + halfExtent

	local cXMin, cYMin, cZMin = posToCell(min.X, min.Y, min.Z, invCellSize)
	local cXMax, cYMax, cZMax = posToCell(max.X, max.Y, max.Z, invCellSize)

	for cx = cXMin, cXMax do
		for cy = cYMin, cYMax do
			for cz = cZMin, cZMax do
				local h = cellToHash(cx, cy, cz, hashtableSize) * U32
				local cbegin = buffer.readu32(cellStarts, h)
				local cend = buffer.readu32(cellStarts, h + U32)
				for i = cbegin, cend - 1 do
					resultCount += 1
					queryResults[resultCount] = buffer.readu32(cellEntries, i * U32)
				end
			end
		end
	end

	return resultCount
end

CompactGrid.multiQueryRegions = function(
	grid: Grid,
	queryOrigins: { Vector3 },
	queryHalfExtents: { Vector3 },
	queryResults: MultiQueryResult
)
	local invCellSize = grid.invCellSize
	local hashtableSize = grid.hashtableSize
	local cellStarts = grid.cellStarts
	local cellEntries = grid.cellEntries

	local queryResultEntries = queryResults.entries
	local queryResultCounts = queryResults.counts

	local n = #queryOrigins

	for i = 1, n do
		queryResultEntries[i] = 0
		queryResultCounts[i] = 0
	end

	local totalResultCount = 0

	for i, origin in queryOrigins do
		local halfExtent = queryHalfExtents[i]
		local resultCount = 0

		local min = origin - halfExtent
		local max = origin + halfExtent

		local cXMin, cYMin, cZMin = posToCell(min.X, min.Y, min.Z, invCellSize)
		local cXMax, cYMax, cZMax = posToCell(max.X, max.Y, max.Z, invCellSize)

		for cx = cXMin, cXMax do
			for cy = cYMin, cYMax do
				for cz = cZMin, cZMax do
					local h = cellToHash(cx, cy, cz, hashtableSize) * U32
					local cbegin = buffer.readu32(cellStarts, h)
					local cend = buffer.readu32(cellStarts, h + U32)
					for k = cbegin, cend - 1 do
						queryResultEntries[totalResultCount + resultCount] = buffer.readu32(cellEntries, k * U32)
						resultCount += 1
					end
				end
			end
		end

		queryResultCounts[i] = totalResultCount
		totalResultCount += resultCount
	end
end

return CompactGrid
