-- luacheck: globals ignore QuickAppBase QuickApp QuickAppChild quickApp fibaro class QuickerAppChild
-- luacheck: globals ignore plugin api net netSync setTimeout clearTimeout setInterval clearInterval json
-- luacheck: globals ignore __assert_type __fibaro_get_device __TAG
-- luacheck: globals ignore utils hc3_emulator FILES urlencode sceneId

-- Same class provided in fibaroExtra.lua
--[[

class 'MyChild'(QuickerAppChild)

function MyChild:__init(args)
  QuickerAppChild.__init(self,args)
end
function MyChild:test()
  self:debug("Child",self.name,self.id)
end

function QuickApp:onInit()
  self:debug(self.name,self.id)
  self.myChild = MyChild{            -- Child will be created if it doesn't exist
    name = "Test",
    uid  = "x",                      -- uid are unique per child, and let us know if they exist or need to be created
    type = "com.fibaro.binarySwitch",
    properties = {},
    interfaces = {"power"},
    quickVars  = { x = 88 }
  }
  child:test()
end
--]]

class 'QuickerAppChild'(QuickAppBase)

local childDevices={}
local uidMap={}
local classNames = {}
local devices=nil

local function setCallbacks(obj,callbacks)
  if callbacks =="" then return end
  local cbs = {}
  for _,cb in ipairs(callbacks or {}) do
    cbs[cb.name]=cbs[cb.name] or {}
    cbs[cb.name][cb.eventType] = cb.callback
  end
  obj.uiCallbacks = cbs
end

local function copy(d) 
  if type(d)=='table' then r = {} for k,v in pairs(d) do r[k]=copy(d) end return r
  else return d end
end

local function getVar(d,var) -- Lookup quickAppVariable from child's property
  for _,v in ipairs(d.properties.quickAppVariables or {}) do
    if v.name==var then return v.value end
  end
end

local function getClassName(f)  -- Get name of class defining __init function
  if classNames[f] then return classNames[f] end -- Cache found names
  for n,v in pairs(_G) do
    pcall(function()
        if type(v)=='userdata' and v.__init == f then
          classNames[f]=n
        end
      end)
    if classNames[f] then return classNames[f] end
  end
end

function QuickApp:initChildDevices()
  self.childDevices = childDevices   -- Set QuickApp's self.childDevices to loaded children
  self.uidMap = uidMap
end

function QuickerAppChild:__init(args)
  assert(args.uid,"QuickerAppChild missing uid")
  if uidMap[args.uid] then
    if not args.silent then fibaro.warning(__TAG,"Child devices "..args.uid.." already exists") end
    return uidMap[args.uid],false
  end
  local props,created,dev,res={},false
  args.className = args.className or getClassName(self.__init) 
  if devices == nil then
    devices = api.get("/devices?parentId="..plugin.mainDeviceId) or {}
  end
  for _,d in ipairs(devices) do
    if getVar(d,"_UID") == args.uid then
      dev = d
      fibaro.trace(__TAG,"Found existing child:"..dev.id)
      break
    end
  end
  local callbacks
  if not dev then
    assert(args.type,"QuickerAppChild missing type")
    assert(args.name,"QuickerAppChild missing name")
    props.parentId = plugin.mainDeviceId
    props.name = args.name
    props.type = args.type
    local properties = args.properties or {}
    args.quickVars = args.quickVars or {}
    local qvars = properties.quickAppVariables or {}
    qvars[#qvars+1]={name="_UID", value=args.uid }--, type='password'}
    qvars[#qvars+1]={name="_className", value=args.className }--, type='password'}
    callbacks = properties.uiCallbacks
    if  callbacks then 
      callbacks = copy(callbacks)
      args.quickVars['_callbacks']=callbacks
    end
    for k,v in pairs(args.quickVars) do qvars[#qvars+1] = {name=k, value=v} end
    properties.quickAppVariables = qvars
    props.initialProperties = properties
    props.initialInterfaces = args.interfaces or {}
    table.insert(props.initialInterfaces,'quickAppChild')
    dev,res = api.post("/plugins/createChildDevice",props)
    if res~=200 then
      error("Can't create child device "..tostring(res).." - "..json.encode(props))
    end
    created = true
    devices = devices or {}
    devices[#devices+1]=dev
    if callbacks then setCallbacks(self,callbacks) end
    fibaro.tracef(__TAG,"Created new child:%s %s",dev.id,dev.type)
  else
    callbacks = getVar(dev,"_callbacks")
  end
  self.uid = args.uid
  if callbacks then setCallbacks(self,callbacks) end
  uidMap[args.uid]=self
  childDevices[dev.id]=self
  QuickAppBase.__init(self,dev) -- Now when everything is done, call base class initiliser...
  self.parent = quickApp
  if self.onInit then self:onInit() end
  return dev,created 
end

function QuickApp:loadQuickerChildren(silent,verifier)
  for _,d in ipairs(api.get("/devices?parentId="..plugin.mainDeviceId) or {}) do
    local uid,flag = getVar(d,'_UID'),true
    local className = getVar(d,'_className')
    if verifier then flag = verifier(d,uid,className) end
    if flag then
      if annotateClass then annotateClass(self,_G[className]) end
      d.uid,d.silent = uid,silent==true
      _G[className](d)
    end
  end
end