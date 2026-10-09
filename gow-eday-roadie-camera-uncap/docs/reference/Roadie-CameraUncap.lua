-- Cheat Engine reference implementation for removing the Roadie Run camera speed cap.
--
-- Requirements:
--   * Cheat Engine attached to GoWEDay.exe.
--   * Campaign loaded far enough for the target camera class to exist.
--   * No other hook installed at the four verified patch sites.
--
-- This script performs no timed capture. It installs the verified correction
-- immediately, records status to a log file, and exposes manual control:
--
--   RoadieCameraUncap.status()
--   RoadieCameraUncap.setEnabled(false)
--   RoadieCameraUncap.setEnabled(true)
--   RoadieCameraUncap.stop()

if RoadieCameraUncap and RoadieCameraUncap.stop then
  pcall(RoadieCameraUncap.stop)
end

local S = {}
RoadieCameraUncap = S

local TARGET_CLASS = 'CamBridge_ViewProcessor_SpeedLimits_RoadieRun_C'

local PROCESSOR_EXIT_SIGNATURE =
  'C4 E2 E1 B9 D1 C5 FB 11 51 10 C5 F8 77 4C 8D 9C 24 20 01 00 00'
local OUTER_EXIT_SIGNATURE =
  '48 8B CB C5 F8 77 E8 ?? ?? ?? ?? C5 F8 77 4C 8D 9C 24 B8 01 00 00'
local SET_ROTATION_SIGNATURE =
  '48 8B C4 48 89 58 08 57 48 81 EC F0 00 00 00 C5 F8 29 70 E8 ' ..
  'C5 FB 10 72 10 C5 F8 29 78 D8 C5 FB 10 7A 08'
local PRIMARY_SET_SIGNATURE =
  '48 8B 06 48 8D 55 F7 48 8B CE FF 90 E8 07 00 00 48 8B CE ' ..
  'E8 ?? ?? ?? ?? 48 85 C0'
local LIMITED_SET_SIGNATURE =
  '48 8B 07 48 8D 54 24 20 C5 FB 11 54 24 28 48 8B CF C5 F8 77 ' ..
  'FF 90 E8 07 00 00 C5 F8 28 74 24 60'

local NAME_POOL_SIGNATURE =
  '48 8D 1D ?? ?? ?? ?? 0F 1F 00 41 8B 04 24 8B C8 C1 E9 10 ' ..
  '0F B7 C0'

local MOVEMENT_TYPE_SIGNATURE =
  '48 63 81 F8 3A 00 00 85 C0 7E 0F 48 8B D0 48 8B 81 F0 3A 00 00 ' ..
  '8A 44 10 FF C3 B0 02 C3'

local function logPath()
  local source = debug.getinfo(1, 'S').source or ''
  if source:sub(1, 1) == '@' then
    local directory = source:sub(2):match('^(.*[\\/])')
    if directory then return directory .. 'Roadie-CameraUncap-status.log' end
  end
  local temporary = os.getenv('TEMP') or '.'
  return temporary .. '\\Roadie-CameraUncap-status.log'
end

local LOG_PATH = logPath()

local function report(message)
  local line = os.date('%Y-%m-%d %H:%M:%S') .. '\t' .. message .. '\n'
  local file = io.open(LOG_PATH, 'ab')
  if file then
    file:write(line)
    file:close()
  end
  print('[RoadieUncap] ' .. message)
end

local function decodeAnsi(bytes, first, count)
  local output = {}
  for index = 0, count - 1 do
    output[#output + 1] = string.char(bytes[first + index])
  end
  return table.concat(output)
end

local function decodeWideAscii(bytes, first, count)
  local output = {}
  for index = 0, count - 1 do
    local low = bytes[first + index * 2]
    local high = bytes[first + index * 2 + 1]
    if high ~= 0 then return nil end
    output[#output + 1] = string.char(low)
  end
  return table.concat(output)
end

local function readName(pool, id)
  id = id & 0xFFFFFFFF
  local block = readQword(pool + 0x10 + (id >> 16) * 8)
  if not block then return nil end
  local entry = block + (id & 0xFFFF) * 2
  local header = readSmallInteger(entry)
  if not header then return nil end
  header = header & 0xFFFF
  local length = header >> 6
  local wide = (header & 1) ~= 0
  if length < 1 then return nil end
  local bytes = readBytes(entry + 2, length * (wide and 2 or 1), true)
  if not bytes then return nil end
  if wide then return decodeWideAscii(bytes, 1, length) end
  return decodeAnsi(bytes, 1, length)
end

local function findNameId(pool, wanted)
  local currentBlock = assert(readInteger(pool + 0x08),
    'Cannot read the FNamePool block index')
  local currentCursor = assert(readInteger(pool + 0x0C),
    'Cannot read the FNamePool cursor')
  assert(currentBlock >= 0 and currentBlock <= 8191,
    'Invalid FNamePool block index')
  assert(currentCursor >= 2 and currentCursor <= 0x20000,
    'Invalid FNamePool cursor')

  for blockIndex = 0, currentBlock do
    local block = assert(readQword(pool + 0x10 + blockIndex * 8),
      'Cannot read an FName block pointer')
    local limit = blockIndex == currentBlock and currentCursor or 0x20000
    local bytes = assert(readBytes(block, limit, true),
      'Cannot read an FName block')
    local offset = 0
    while offset + 2 <= limit do
      local first = offset + 1
      local header = bytes[first] | (bytes[first + 1] << 8)
      if header == 0 then break end
      local length = header >> 6
      local wide = (header & 1) ~= 0
      assert(length >= 1, 'Invalid FName entry')
      local payload = length * (wide and 2 or 1)
      local total = (2 + payload + 1) & ~1
      if offset + total > limit then break end
      if length == #wanted then
        local value
        if wide then
          value = decodeWideAscii(bytes, first + 2, length)
        else
          value = decodeAnsi(bytes, first + 2, length)
        end
        if value == wanted then
          return (blockIndex << 16) | (offset >> 1)
        end
      end
      offset = offset + total
    end
  end
  error('Target class FName was not found; load Campaign before running the script')
end

local function imageSize(base)
  local peOffset = assert(readInteger(base + 0x3C), 'Cannot read DOS header')
  return assert(readInteger(base + peOffset + 0x50),
    'Cannot read SizeOfImage')
end

local function scanModule(base, size, pattern)
  local results = AOBScan(pattern, '+X-C-W', 0, '')
  local matches = {}
  if results then
    for index = 0, results.Count - 1 do
      local address = tonumber(results[index], 16)
      if address >= base and address < base + size then
        matches[#matches + 1] = address
      end
    end
    results.destroy()
  end
  return matches
end

local function uniqueSignature(base, size, pattern, offset, label)
  local matches = scanModule(base, size, pattern)
  assert(#matches == 1,
    string.format('%s signature produced %d module matches', label, #matches))
  return matches[1] + offset
end

local function signed32(value)
  if value >= 0x80000000 then return value - 0x100000000 end
  return value
end

local function resolveRip(instruction, adjustment)
  local displacement = assert(readInteger(instruction + 3),
    'Cannot read RIP displacement')
  return instruction + 7 + signed32(displacement) + adjustment
end

local function resolveNamePool(base, size)
  local reference = uniqueSignature(
    base, size, NAME_POOL_SIGNATURE, 0, 'FNamePool')
  return resolveRip(reference, -0x10)
end

local function initializeSharedData(data)
  assert(writeBytes(data, 0))       -- +0x00 correction enabled
  assert(writeQword(data + 0x08, 0)) -- processor hits
  assert(writeQword(data + 0x10, 0)) -- corrected frames
  assert(writeQword(data + 0x18, 0)) -- raw delta Yaw
  assert(writeQword(data + 0x20, 0)) -- limited delta Yaw
  assert(writeBytes(data + 0x38, 0)) -- processor result pending
  assert(writeQword(data + 0x60, 0)) -- primary controller
  assert(writeQword(data + 0x68, 0)) -- primary Yaw
  assert(writeQword(data + 0x78, 0)) -- synchronized sets
  assert(writeBytes(data + 0x88, 0)) -- primary result valid
  assert(writeQword(data + 0x90, 0)) -- movement type corrections
end

local function main()
  local base = assert(getAddressSafe('GoWEDay.exe'),
    'Attach Cheat Engine to GoWEDay.exe first')
  S.pid = getOpenedProcessID()
  assert(S.pid ~= 0, 'Game is not attached')

  local size = imageSize(base)
  local processorSite = uniqueSignature(base, size,
    PROCESSOR_EXIT_SIGNATURE, 10, 'processor wrapper exit')
  local outerSite = uniqueSignature(base, size,
    OUTER_EXIT_SIGNATURE, 11, 'processor-chain commit')
  local setRotationSite = uniqueSignature(base, size,
    SET_ROTATION_SIGNATURE, 0, 'SetControlRotation')
  local movementTypeSite = uniqueSignature(base, size,
    MOVEMENT_TYPE_SIGNATURE, 0, 'movement rotation type getter')
  local primarySetCaller = uniqueSignature(base, size,
    PRIMARY_SET_SIGNATURE, 16, 'ordinary SetControlRotation caller')
  local limitedSetCaller = uniqueSignature(base, size,
    LIMITED_SET_SIGNATURE, 26, 'Roadie SetControlRotation caller')

  local pool = resolveNamePool(base, size)
  assert(readName(pool, 0) == 'None', 'FNamePool validation failed')
  local targetId = findNameId(pool, TARGET_CLASS)

  local processorOriginal = assert(readBytes(processorSite, 11, true),
    'Cannot save processor wrapper instructions')
  local outerOriginal = assert(readBytes(outerSite, 11, true),
    'Cannot save processor-chain instructions')
  local setRotationOriginal = assert(readBytes(setRotationSite, 7, true),
    'Cannot save SetControlRotation instructions')
  local movementTypeOriginal = assert(readBytes(movementTypeSite, 7, true),
    'Cannot save movement rotation type instructions')

  local processorCode = assert(allocateMemory(0x1000, processorSite),
    'Cannot allocate memory near the processor wrapper')
  local outerCode = assert(allocateMemory(0x1000, outerSite),
    'Cannot allocate memory near the processor-chain commit')
  local setRotationCode = assert(allocateMemory(0x1000, setRotationSite),
    'Cannot allocate memory near SetControlRotation')
  local movementTypeCode = assert(allocateMemory(0x1000, movementTypeSite),
    'Cannot allocate memory near the movement rotation type getter')
  assert(math.abs(processorCode - processorSite) < 0x7FFFF000,
    'Processor relay allocation is outside rel32 range')
  assert(math.abs(outerCode - outerSite) < 0x7FFFF000,
    'Outer relay allocation is outside rel32 range')
  assert(math.abs(setRotationCode - setRotationSite) < 0x7FFFF000,
    'SetControlRotation relay allocation is outside rel32 range')
  assert(math.abs(movementTypeCode - movementTypeSite) < 0x7FFFF000,
    'Movement rotation type relay allocation is outside rel32 range')

  local data = assert(allocateMemory(0x100),
    'Cannot allocate shared hook data')
  initializeSharedData(data)

  local assembly = string.format([[
define(PROCESSOREXIT,%X)
define(OUTEREXIT,%X)
define(SETROTATION,%X)
define(PROCESSORCODE,%X)
define(OUTERCODE,%X)
define(SETCODE,%X)
define(DATA,%X)
define(TARGETID,%X)
define(PRIMARYCALLER,%X)
define(LIMITEDCALLER,%X)
define(MOVEMENTTYPE,%X)
define(MOVEMENTCODE,%X)
label(processorDone)
label(outerDone)
label(outerApply)
label(setOriginalCode)
label(setCapturePrimary)
label(setOverrideLimited)
label(movementDefault)
label(movementDone)

PROCESSORCODE:
  pushfq
  push rax
  push rcx
  push rdx
  push r8
  push r9
  push r10
  push r11
  lea r10,[rsp+40]
  mov r11,DATA
  cmp byte ptr [r11],1
  jne processorDone
  mov rax,[rbx+10]
  test rax,rax
  je processorDone
  cmp dword ptr [rax+18],TARGETID
  jne processorDone
  mov rax,[r10+178]
  mov rdx,[r10+188]
  test rax,rax
  je processorDone
  test rdx,rdx
  je processorDone
  mov rcx,[rax+08]
  mov rax,[rdx+08]
  mov [r11+18],rcx
  mov [r11+20],rax
  mov byte ptr [r11+38],1
  lock inc qword ptr [r11+08]
processorDone:
  pop r11
  pop r10
  pop r9
  pop r8
  pop rdx
  pop rcx
  pop rax
  popfq
  vzeroupper
  lea r11,[rsp+120]
  jmp PROCESSOREXIT+B

OUTERCODE:
  pushfq
  push rax
  push r11
  sub rsp,10
  vmovdqu [rsp],xmm0
  mov r11,DATA
  cmp byte ptr [r11],1
  jne outerDone
  cmp byte ptr [r11+38],1
  jne outerDone
outerApply:
  mov byte ptr [r11+38],0
  test rdi,rdi
  je outerDone
  vmovsd xmm0,[r11+18]
  vsubsd xmm0,xmm0,[r11+20]
  vaddsd xmm0,xmm0,[rdi+08]
  vmovsd [rdi+08],xmm0
  lock inc qword ptr [r11+10]
outerDone:
  vmovdqu xmm0,[rsp]
  add rsp,10
  pop r11
  pop rax
  popfq
  vzeroupper
  lea r11,[rsp+1B8]
  jmp OUTEREXIT+B

SETCODE:
  mov rax,DATA
  cmp byte ptr [rax],1
  jne setOriginalCode
  test rdx,rdx
  je setOriginalCode
  mov r10,[rsp]
  mov r11,LIMITEDCALLER
  cmp r10,r11
  je setOverrideLimited
  mov r11,PRIMARYCALLER
  cmp r10,r11
  je setCapturePrimary
  jmp setOriginalCode
setCapturePrimary:
  mov [rax+60],rcx
  mov r11,[rdx+08]
  mov [rax+68],r11
  mov byte ptr [rax+88],1
  jmp setOriginalCode
setOverrideLimited:
  cmp byte ptr [rax+88],1
  jne setOriginalCode
  cmp rcx,[rax+60]
  jne setOriginalCode
  mov byte ptr [rax+88],0
  mov r11,[rax+68]
  mov [rdx+08],r11
  lock inc qword ptr [rax+78]
setOriginalCode:
  mov rax,rsp
  mov [rax+08],rbx
  jmp SETROTATION+7

MOVEMENTCODE:
  movsxd rax,dword ptr [rcx+3AF8]
  test eax,eax
  jle movementDefault
  mov rdx,rax
  mov rax,[rcx+3AF0]
  mov al,[rax+rdx-1]
  cmp al,1
  jne movementDone
  mov r11,DATA
  cmp byte ptr [r11],1
  jne movementDone
  lock inc qword ptr [r11+90]
movementDefault:
  mov al,2
movementDone:
  ret

PROCESSOREXIT:
  jmp PROCESSORCODE
  nop 6
OUTEREXIT:
  jmp OUTERCODE
  nop 6
SETROTATION:
  jmp SETCODE
  nop 2
MOVEMENTTYPE:
  jmp MOVEMENTCODE
  nop 2
]], processorSite, outerSite, setRotationSite, processorCode, outerCode,
    setRotationCode, data, targetId, primarySetCaller, limitedSetCaller,
    movementTypeSite, movementTypeCode)

  S.processorSite = processorSite
  S.processorOriginal = processorOriginal
  S.outerSite = outerSite
  S.outerOriginal = outerOriginal
  S.setRotationSite = setRotationSite
  S.setRotationOriginal = setRotationOriginal
  S.movementTypeSite = movementTypeSite
  S.movementTypeOriginal = movementTypeOriginal
  S.data = data
  S.logPath = LOG_PATH

  function S.setEnabled(enabled)
    assert(getOpenedProcessID() == S.pid,
      'Attach Cheat Engine to the original game process')
    assert(writeBytes(S.data, enabled and 1 or 0))
    report(enabled and 'correction ON' or 'correction OFF')
  end

  function S.status()
    assert(getOpenedProcessID() == S.pid,
      'Attach Cheat Engine to the original game process')
    local enabled = (readBytes(S.data, 1, false) or 0) ~= 0
    local processorHits = readQword(S.data + 0x08) or 0
    local correctedFrames = readQword(S.data + 0x10) or 0
    local synchronizedSets = readQword(S.data + 0x78) or 0
    local movementCorrections = readQword(S.data + 0x90) or 0
    report(string.format(
      'STATUS enabled=%s processor_hits=%d corrected_frames=%d synchronized_sets=%d movement_corrections=%d',
      tostring(enabled), processorHits, correctedFrames, synchronizedSets,
      movementCorrections))
  end

  function S.stop()
    if getOpenedProcessID() ~= S.pid then
      report('game process is no longer attached; nothing remains to restore')
      return
    end
    writeBytes(S.data, 0)
    if S.installed then
      assert(writeBytes(S.processorSite, table.unpack(S.processorOriginal)))
      assert(writeBytes(S.outerSite, table.unpack(S.outerOriginal)))
      assert(writeBytes(S.setRotationSite,
        table.unpack(S.setRotationOriginal)))
      assert(writeBytes(S.movementTypeSite,
        table.unpack(S.movementTypeOriginal)))
      S.installed = false
    end
    S.status()
    report('hook removed; allocated scratch memory remains until process exit')
  end

  local installed, installError = autoAssemble(assembly)
  assert(installed,
    'Complete hook installation failed: ' .. tostring(installError))
  S.installed = true
  S.setEnabled(true)
  report(string.format(
    'READY target FName=0x%X; native correction installed', targetId))
  report('log file: ' .. LOG_PATH)
end

local ok, failure = xpcall(main, debug.traceback)
if not ok then
  if S.stop then pcall(S.stop) end
  report('ERROR ' .. tostring(failure))
end
