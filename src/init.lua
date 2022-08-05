--!strict
local _packages = script.Parent
local _package = script
local _require = require(script.Require)

local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")

--- @class NodeUtil
--- A long list of useful node related functions.
local NodeUtil = {}

NodeUtil.__index = NodeUtil


NodeUtil.BackendTagPrefix = "_NODETAG_"

--- @prop BackendTagPrefix string
--- @within NodeUtil
--- to avoid overlapping with front-end tags, all tags are appended on the backend with a tag prefix

export type Node = Model

--- @type Node Model
--- @within NodeUtil
--- A model that can be run through the NodeUtil functions

type Connection = ObjectValue
type SolverConnection = ObjectValue

--get node generation
function _getNodeGeneration(node: Node): number
	return node:GetAttribute("_GenerationIndex") or 0
end

--set node generation
function _setNodeGeneration(node: Node, number: number): nil
	node:SetAttribute("_GenerationIndex", number)
	return nil
end

--gets the connection folder, erroring if one doesnt' exist
function _getConnectionFolder(node: Node): Folder
	local connectionFolder: Instance? = node:FindFirstChild("Connections")
	assert(connectionFolder ~= nil and connectionFolder.Name == "Connections" and connectionFolder:IsA("Folder"), "Bad node")
	return connectionFolder
end

--gets the solver folder, erroring if one doesnt' exist
function _getSolverFolder(node: Node): Folder
	local solverFolder: Instance? = node:FindFirstChild("Solvers")
	assert(solverFolder ~= nil and solverFolder.Name == "Solvers" and solverFolder:IsA("Folder"), "Bad node")
	return solverFolder
end

--gets the solver folder, erroring if one doesnt' exist
function _getSolverModule(node: Node, key: string): ModuleScript
	local solverFolder: Folder = _getSolverFolder(node)
	local objVal: Instance? = solverFolder:FindFirstChild(key)
	assert(objVal ~= nil and objVal:IsA("ObjectValue"))
	local val:Instance? = objVal.Value
	assert(val ~= nil and val:IsA("ModuleScript"))
	return val
end

--finds connection, will return nil if one doesn't exist
function _findConnection(node: Node, other: Node): Connection?
	local connectionFolder: Folder = _getConnectionFolder(node)
	local inst: Instance? = connectionFolder:FindFirstChild(other.Name)
	if inst then
		assert(inst:IsA("ObjectValue"), "Bad connection")
		return inst
	end
	return nil
end

-- gets connection, errors if one doesn't exist
function _getConnection(node: Node, other: Node): Connection
	local inst: ObjectValue? = _findConnection(node, other)
	assert(inst ~= nil)
	return inst
end

function _embedList(data: {[string]: any}, folder: Folder?): Folder
	folder = folder or Instance.new("Folder")
	assert(folder ~= nil and folder:IsA("Folder"))
	--clear preview values
	for k, v: any in pairs(folder:GetAttributes()) do
		folder:SetAttribute(k, nil)
	end

	--set new values
	for k, v: any in pairs(data) do
		folder:SetAttribute(k, v)
	end

	return folder
end

function _getNodeCache(node: Node): Folder
	local cache:Instance? = node:FindFirstChild("Cache")
	assert(cache ~= nil and cache:IsA("Folder"))
	return cache
end

function _setNodeCache(node: Node): Folder
	local mainNodeCache: Folder = _embedList(node:GetAttributes(), _getNodeCache(node))
	mainNodeCache.Name = "Cache"

	--update new subcaches
	local connectedNodes = NodeUtil.getConnectedNodes(node)
	local nodeDict: {[string]: Node?} = {}
	for i, otherNode: Node in ipairs(connectedNodes) do
		local oldSubCache: any? = mainNodeCache:FindFirstChild(otherNode.Name)
		local subNodeCache: Folder = _embedList(otherNode:GetAttributes(), oldSubCache)
		subNodeCache.Name = otherNode.Name
		subNodeCache.Parent = mainNodeCache
		nodeDict[otherNode.Name] = otherNode
	end

	--clear any old subcaches that are no longer connected
	for i, subCache: Instance in ipairs(mainNodeCache:GetChildren()) do
		assert(subCache:IsA("Folder"))
		if nodeDict[subCache.Name] == nil then
			subCache:Destroy()
		end
	end
	return mainNodeCache
end

function _getIfNodeChanged(node: Node, cache: Folder?): boolean
	cache = cache or _getNodeCache(node)
	assert(cache ~= nil)
	cache = cache :: Folder
	local cachedValues = cache:GetAttributes()
	local currentValues = node:GetAttributes()
	for k, v in pairs(cachedValues) do
		if currentValues[k] ~= cachedValues[k] then
			return true
		end
	end
	for k, v in pairs(currentValues) do
		if currentValues[k] ~= cachedValues[k] then
			return true
		end
	end
	return false
end

function _getIfNodeNeedsToSolve(node: Node): boolean
	if _getIfNodeChanged(node) then return true end
	local cache =_getNodeCache(node)
	local connectedNodes = NodeUtil.getConnectedNodes(node)
	if #cache:GetChildren() ~= #connectedNodes then return true end
	for i, otherNode: Node in ipairs(connectedNodes) do
		local otherNodeCache:Instance? = cache:FindFirstChild(otherNode.Name)
		if not otherNodeCache then return true end
		assert(otherNodeCache ~= nil and otherNodeCache:IsA("Folder"))
		if _getIfNodeChanged(otherNode, otherNodeCache) then return true end
	end
	return false
end

function _getOutputSolver(node: Node, key: string): ((node: Node) -> any?)
	local module = _getSolverModule(node, key)
	local solver = _require(module)
	solver = solver :: ((node: Node) -> any?)
	return solver
end


-- converts to a raw tag
function _toRawTag(tag: string): string
	return NodeUtil.BackendTagPrefix..tag
end
-- converts back to a normal front-end tag
function _fromRawTag(rawTag: string): string
	return string.gsub(rawTag, NodeUtil.BackendTagPrefix, "")
end
-- checks if tag is a raw tag
function _isRawTag(tag: string): boolean
	return string.find(tag, NodeUtil.BackendTagPrefix) == nil
end

function _removeConnectionTag(connection: Connection, tag: string)
	CollectionService:RemoveTag(connection, _toRawTag(tag))
end
function _setConnectionTag(connection: Connection, tag: string)
	CollectionService:AddTag(connection, _toRawTag(tag))
end

function _getConnectionTags(connection: Connection): {[number]: string}
	local tags: {[number]: string} = {}
	for i, rawTag in ipairs(CollectionService:GetTags(connection)) do
		table.insert(tags, _fromRawTag(rawTag))
	end
	return tags
end

function _connectionHasTag(connection: Connection, tag: string): boolean
	return CollectionService:HasTag(connection, _toRawTag(tag))
end

--- Checks if two nodes share a connection
function NodeUtil.isConnected(node: Node, other: Node): boolean
	assert(node ~= other, "Nodes need to be different")
	return _findConnection(node, other) ~= nil
end

--- Removes the connection from both nodes
function NodeUtil.disconnect(node: Node, other:Node): nil
	assert(node ~= other, "Nodes need to be different")
	if not NodeUtil.isConnected(node, other) then return end

	local connection = _getConnection(node, other)	
	connection:Destroy()

	NodeUtil.disconnect(other, node)
	return nil
end

--- Sets the tag of a connection
function NodeUtil.setConnectionTag(node: Node, other: Node, tag: string)
	assert(node ~= other, "Nodes need to be different")
	local connection: ObjectValue = _getConnection(node, other)
	_setConnectionTag(connection, tag)
end

--- Gets the tags of a connection
function NodeUtil.getConnectionTags(node: Node, other: Node): {[number]: string}
	assert(node ~= other, "Nodes need to be different")
	local connection: ObjectValue = _getConnection(node, other)
	return _getConnectionTags(connection)
end

--- Gets if a connection has a tag
function NodeUtil.getIfConnectionHasTag(node: Node, other: Node, tag: string): boolean
	assert(node ~= other, "Nodes need to be different")
	local connection: ObjectValue = _getConnection(node, other)
	return _connectionHasTag(connection, tag)
end

--- Gets if a connection has a tag
function NodeUtil.removeConnectionTag(node: Node, other: Node, tag: string): nil
	assert(node ~= other, "Nodes need to be different")
	local connection: ObjectValue = _getConnection(node, other)
	_removeConnectionTag(connection, tag)
	return nil
end

--- Creates a connection between two nodes.
function NodeUtil.connect(node: Node, other: Node, tagOrTagList: ({[number]: string} | string)?, position: Vector3?): nil
	if NodeUtil.isConnected(node, other) then return end
	assert(node ~= other, "Nodes need to be different")
	local connectionFolder: Folder = _getConnectionFolder(node)

	local connection: ObjectValue = Instance.new("ObjectValue")
	connection.Name = other.Name
	connection.Value = other
	connection.Parent = connectionFolder

	if position then
		connection:SetAttribute("Position", position)
	end

	if typeof(tagOrTagList) == "string" then
		_setConnectionTag(connection, tagOrTagList)
	elseif typeof(tagOrTagList) == "table" then
		for i, tag in ipairs(tagOrTagList) do
			_setConnectionTag(connection, tag)
		end
	end

	NodeUtil.connect(other, node, tagOrTagList, position)
	return nil
end

--- Sets the position of a connection between two nodes. Will error if no connection exists. Can be used to erase position if nil is passed as position parameter.
function NodeUtil.setConnectionPosition(node: Node, other: Node, position: Vector3?): nil
	assert(node ~= other, "Nodes need to be different")
	local connection = _getConnection(node, other)
	connection:SetAttribute("Position", position)

	local otherConnection = _getConnection(other, node)
	otherConnection:SetAttribute("Position", position)
	
	return nil
end

--- Gets the position of a connection between two nodes. Will error if no connection exists. Will return nil if position was never set.
function NodeUtil.getConnectionPosition(node: Node, other: Node): Vector3?
	local connection = _getConnection(node, other)
	local val: any? = connection:GetAttribute("Position")
	if val ~= nil then
		assert(typeof(val) == "Vector3")
		return val
	end
	return nil
end

--- Returns a list of all nodes that are connected
function NodeUtil.getConnectedNodes(node: Node): {[number]: Node}
	local nodes: {[number]: Node} = {}
	for i, connection in ipairs(_getConnectionFolder(node):GetChildren()) do
		assert(connection:IsA("ObjectValue"))
		local otherNode: Instance? = connection.Value
		if otherNode ~= nil then
			assert(otherNode:IsA("Model"))
			table.insert(nodes, otherNode)
		end
	end
	return nodes
end

--- Returns a list of all nodes that match the tag
function NodeUtil.getConnectedNodesOfTag(node: Node, tag: string): {[number]: Node}
	local nodes: {[number]: Node} = {}
	for i, otherNode in ipairs(NodeUtil.getConnectedNodes(node)) do
		if NodeUtil.getIfConnectionHasTag(node, otherNode, tag) then
			table.insert(nodes, otherNode)
		end
	end
	return nodes
end

--- Set non-solved properties properties manually
function NodeUtil.setInputValue(node: Node, key: string, val: any?): nil
	local solverFolder: Folder = _getSolverFolder(node)
	local inst: Instance? = solverFolder:FindFirstChild(key)
	assert(inst == nil, "Can't reuse output keys in input")
	node:SetAttribute(key, val)
	return nil
end

--- Get the value of non-solver properties
function NodeUtil.getInputValue(node: Node, key: string): any?
	return node:SetAttribute(key)
end

--- Set a module to be used for future solving of the value
function NodeUtil.setOutputSolver(node: Node, key: string, solver: ModuleScript): nil
	local solverFolder: Folder = _getSolverFolder(node)
	assert(node:GetAttribute(key) == nil, "Can't reuse input keys in output")

	local objVal = Instance.new("ObjectValue")
	objVal.Name = key
	objVal.Value = solver
	objVal.Parent = solverFolder

	return nil
end

--- Sets the position of a node
function NodeUtil.setNodePosition(node: Node, position: Vector3): nil
	node:SetAttribute("Position", position)
	return nil
end

--- Gets the position of a node
function NodeUtil.getNodePosition(node: Node): Vector3
	local val: any? = node:SetAttribute("Position")
	assert(val ~= nil and typeof(val) == "Vector3")
	return val
end

-- runs through and updates the outputs
function NodeUtil.solve(node: Node)
	if not _getIfNodeNeedsToSolve(node) then return end
	_setNodeGeneration(node, _getNodeGeneration(node) + 1)
	_setNodeCache(node)
	for i, solverConnection: Instance in ipairs(_getSolverFolder(node):GetChildren()) do
		assert(solverConnection:IsA("ObjectValue"))
		local solver = _getOutputSolver(node, solverConnection.Name)
		node:SetAttribute(solverConnection.Name, solver(node))
	end
end

--- Constructs a new node at the specified position. 
function NodeUtil.new(position: Vector3): Node
	local node: Node = Instance.new("Model")
	node:SetAttribute("Position", position)
	node.Name = HttpService:GenerateGUID(false)

	local connectionFolder: Folder = Instance.new("Folder")
	connectionFolder.Name = "Connections"
	connectionFolder.Parent = node

	local solverFolder: Folder = Instance.new("Folder")
	solverFolder.Name = "Solvers"
	solverFolder.Parent = node

	local cacheFolder: Folder = Instance.new("Folder")
	cacheFolder.Name = "Cache"
	cacheFolder.Parent = node

	return node
end

export type NodeUtil = typeof(NodeUtil)

return NodeUtil