--print("The 8086/8088 Emulator")

term.clear()
term.setCursorPos(1,1)
print("The 8086/8088 Emulator")
os.sleep(0.5)
term.clear()
os.sleep(0.5)
local mem = {}
for i=0,0xFFFFF do
	mem[i] = 0
end



local regs16 = {0x0000, 0x0000, 0x0000, 0x0100, 0x0000, 0x0000, 0x0000} --16-bit regs AX, BX, CX, DX, SI, DI, BP, SP
regs16[0] = 0x0000
local segs = {0xFFFF, 0x0000, 0x0000} --16-bit segment regs CS, DS, ES, SS
segs[0] = 0x0000
local regs8 = {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00} --8-bit regs AL, AH, BL, BH, CL, CH, DL, DH
regs8[0] = 0x00
local ip = 0x0000
local addr = 0x00000

local FLAG_CF = 0 --carry
local FLAG_PF = 0 --parity
local FLAG_AF = 0 --adjust
local FLAG_ZF = 0 --zero
local FLAG_SF = 0 --sign
local FLAG_TF = 0 --trap
local FLAG_IF = 0 --IF
local FLAG_DF = 0 --direction
local FLAG_OF = 0 --overflow

local AX = 0
local CX = 1
local DX = 2
local BX = 3
local SP = 4
local BP = 5
local SI = 6
local DI = 7

local ES = 0
local CS = 1
local SS = 2
local DS = 3

local AL = 0
local CL = 1
local DL = 2
local BL = 3
local AH = 4
local CH = 5
local DH = 6
local BH = 7

local function pack_flags()
	local result
	result = FLAG_CF + 0x2 + (FLAG_PF * 0x4) + 0x8 + (FLAG_AF * 0x10) + 0x20 + (FLAG_ZF * 0x40) + (FLAG_SF * 0x80) + (FLAG_TF * 0x100) + (FLAG_IF * 0x200) + (FLAG_DF * 0x400) + (FLAG_OF * 0x800) + 0xF000
	return result
end

local function print_regs()
	print("AX:" .. string.format("%04x", regs16[AX]) .. " BX:" .. string.format("%04x", regs16[BX]) .. " CX:" .. string.format("%04x", regs16[CX]) .. " DX:" .. string.format("%04x", regs16[DX]))
	print("SI:" .. string.format("%04x", regs16[SI]) .. " DI:" .. string.format("%04x", regs16[DI]) .. " BP:" .. string.format("%04x", regs16[BP]) .. " SP:" .. string.format("%04x", regs16[SP]))
	print("CS:" .. string.format("%04x", segs[CS]) .. " DS:" .. string.format("%04x", segs[DS]) .. " ES:" .. string.format("%04x", segs[ES]) .. " SS:" .. string.format("%04x", segs[SS]))
	print("IP:" .. string.format("%0x04", ip))
	print("FLAGS: " .. string.format("%04x", pack_flags()))
end
local function dump_mem()
	local output = ""
	for i=0, 1023, 16 do
		for j=0, 15 do
			output = output .. " " .. string.format("%02x", mem[i + j])
		end
		print(string.format("%04x", i) .. ":" .. string.format(output))
		output = ""
	end
end

local function read_reg8(n)
	local result
	if n == AL then
		result = regs16[AX] % 0x100
	elseif n == CL then
		result = regs16[CX] % 0x100
	elseif n == DL then
		result = regs16[DX] % 0x100
	elseif n == BL then
		result = regs16[BX] % 0x100
	elseif n == AH then
		result = math.floor(regs16[AX] / 0x100)
	elseif n == CH then
		result = math.floor(regs16[CX] / 0x100)
	elseif n == DH then
		result = math.floor(regs16[DX] / 0x100)
	elseif n == BH then
		result = math.floor(regs16[BX] / 0x100)
	end
	
	return result
end

local function write_reg16(reg, value)
	
end

local function write_reg8(reg, value)
	if value > 0xFF then
		value = value - 0x100
	end
	
	if reg == AL then
		regs16[AX] = (math.floor(regs16[AX] / 0x100) * 0x100) + value
	elseif reg == CL then
		regs16[CX] = (math.floor(regs16[CX] / 0x100) * 0x100) + value
	elseif reg == DL then
		regs16[DX] = (math.floor(regs16[DX] / 0x100) * 0x100) + value
	elseif reg == BL then
		regs16[BX] = (math.floor(regs16[BX] / 0x100) * 0x100) + value
	elseif reg == AH then
		regs16[AX] = regs16[AX] % 0x100 + (value * 0x100)
	elseif reg == CH then
		regs16[CX] = regs16[CX] % 0x100 + (value * 0x100)
	elseif reg == DH then
		regs16[DX] = regs16[DX] % 0x100 + (value * 0x100)
	elseif reg == BH then
		regs16[BX] = regs16[BX] % 0x100 + (value * 0x100)
	end
end

local function inc_ip() --increment instruction pointer
	if (ip > 0xFFFF) then
		ip = ip - 0x10000
	else
		ip = ip + 1
	end
	return ip
end

local function mrm16(val)
	local result = {}
	local mod
	local reg
	local rm
	--mode
	if math.floor(val / 0x40) == 0 then
		if val % 0x8 == 0x6 then
			mod = "direct"
		else
			mod = "nodisp"
		end
	elseif math.floor(val / 0x40) == 1 then
		mod = "disp8"
	elseif math.floor(val / 0x40) == 2 then
		mod = "disp16"
	elseif math.floor(val / 0x40) == 3 then
		mod = "reg"
	end
	--register
	reg = math.floor((val % 0x40) / 0x8)
	rm = val % 0x8
	result[0] = mod
	result[1] = reg
	result[2] = rm
	
	return result
end

local function decode_inst(inst)
	local mrm = {}
	if inst == 0x00 then --ADD r/m8, reg8 TODO: Flags
		mrm = mrm16(mem[inc_ip()])
		local target
		if mrm[0] == "direct" then
			local target = mem[inc_ip()] + (mem[inc_ip()] * 0x100)
			local sum = mem[target] + read_reg8(mrm[1])
			if sum > 0xFF then
				sum = value - 0x100
				FLAG_CF = 1
			end
			mem[target] = sum
		elseif mrm[0] == "disp16" then
			local target = mem[inc_ip()] + (mem[inc_ip()] * 0x100) + (segs[mrm[2]] * 0x10)
			local sum = mem[target] + read_reg8(mrm[1])
			if sum > 0xFF then
				sum = value - 0x100
				FLAG_CF = 1
			end
			mem[target] = sum
		elseif mrm[0] == "disp8" then
			local target = mem[inc_ip]
			if target > 0x80 then
				target = target + 0xff00
			end
			target = target + (segs[mrm[2]] * 0x10)
			mem[target] = mem[target] + read_reg8(mrm[1])
		elseif mrm[0] == "reg" then
			
			write_reg8(mrm[1], read_reg8(mrm[1]) + read_reg8(mrm[2]))
		end
	end
	if inst == 0x01 then --ADD r/m16,reg16
		mrm = mrm16(mem[inc_ip()])
		
		if mrm[0] == "direct" then
			local target = mem[inc_ip()] + (mem[inc_ip()] * 0x100)
			local sum = mem[target] + regs16[mrm[1]]
			if sum > 0xFFFF then
				sum = sum - 0x10000
			end
			mem[target] = sum
		elseif mrm[0] == "disp16" then
			local target = mem[inc_ip()] + (mem[inc_ip()] * 0x100) + (segs[mrm[2]] * 0x10)
			mem[target] = mem[target] + regs16[mrm[1]]
		elseif mrm[0] == "disp8" then
			
		elseif mrm[0] == "reg" then
			regs16[mrm[1]] = regs16[mrm[1]] + regs16[mrm[2]]
		end
	end
	if inst == 0x88 then
		mrm = mrm16(mem[inc_ip()])
		
		if mrm[0] == "direct" then --MOV r/m8,reg8 TODO: Fix disp8
			local target = mem[inc_ip()] + (mem[inc_ip()] * 0x100)
			regs8[mrm[1]] = (mem[target] * 0x100) + mem[target + 1]
		elseif mrm[0] == "disp16" then
			local target = mem[inc_ip()] + (mem[inc_ip()] * 0x100) + (segs[mrm[2]] * 0x10)
			regs8[mrm[1]] = (mem[target] * 0x100) + mem[target + 1]
		elseif mrm[0] == "disp8" then
			local target = mem[inc_ip]
			if target > 0x80 then
				target = target + 0xff00
			end
			regs8[mrm[1]] = target + (segs[mrm[2]] * 0x10)
		elseif mrm[0] == "reg" then
			regs8[mrm[1]] = regs16[mrm[2]]
		end
	end
	if inst == 0x89 then --MOV r/m16,reg16
		mrm = mrm16(mem[inc_ip()])
		if mrm[0] == "direct" then
			local target = mem[inc_ip()] + (mem[inc_ip()] * 0x100)
			regs16[mrm[1]] = (mem[target] * 0x100) + mem[target + 1]
		elseif mrm[0] == "disp16" then
			local target = mem[inc_ip()] + (mem[inc_ip()] * 0x100) + (segs[mrm[2]] * 0x10)
			regs16[mrm[1]] = (mem[target] * 0x100) + mem[target + 1]
		elseif mrm[0] == "disp8" then
			local target = mem[inc_ip]
			if target > 0x80 then
				target = target + 0xff00
			end
			regs16[mrm[1]] = target + (segs[mrm[2]] * 0x10)
		elseif mrm[0] == "reg" then
			regs16[mrm[1]] = regs16[mrm[2]]
		end
	end
	if inst == 0x8F then --POP r/m16
		
	end
	if inst == 0xA0 then --MOV AL,mem8
		write_reg8(AL, mem[mem[inc_ip()]])
	end
	if inst == 0xA1 then --MOV AX,mem16
		local target = (mem[inc_ip()] * 0x100) + mem[inc_ip()]
		regs16[AX] = mem[target * 0x100] + mem[target + 1]
	end
	if inst == 0xA2 then --MOV mem8,AL
		mem[mem[inc_ip()]] = regs16[AX] % 0x100
	end
	if inst == 0xA3 then --MOV mem16,AX
		local target = mem[inc_ip()] + (mem[inc_ip()] * 0x100)
		mem[target] = regs16[AX] / 0x100
		mem[target + 1] = regs16[AX] % 0x100
	end
	if (inst >= 0xB0 and inst < 0xB8) then --MOV reg8,imm8
		write_reg8(inst - 0xB0, mem[inc_ip()])
	end
	if (inst >= 0xB8 and inst < 0xC0) then --MOV reg16,imm16
		regs16[inst - 0xB8] = (mem[inc_ip()] * 0x100) + mem[inc_ip()]
	end
	if inst == 0xC0 then --MOV r/m8, imm8
		--cpu_mov8(mem[inc_ip()], mem[inc_ip()])
	end
	if inst == 0xFC then --CLD
		FLAG_DF = 0
	end
	if inst == 0xFD then --STD
		FLAG_DF = 1
	end
	if inst == 0xEA then --JMP 
		regs16[CS] = (mem[inc_ip()] * 0x100) + mem[inc_ip()]
		ip = 0 --(mem[inc_ip()] * 0x100) + mem[inc_ip()]
	end
end
--TEST
mem[0] = 0xBC --MOV SP,600h
mem[1] = 0x06
mem[2] = 0x00
--mem[3] = 0xFF
--mem[4] = 0x00 --ADD AL,DL
--mem[5] = 0xC2
--mem[4] = 0xD8
--mem[5] = 0x00 --ADD CL,DL
--mem[6] = 0xD3


mem[0xFFFF0] = 0xBC --MOV SP,400h
mem[0xFFFF1] = 0x04
mem[0xFFFF2] = 0x00
mem[0xFFFF3] = 0xEA --JMP 0000:0000
mem[0xFFFF4] = 0x00
mem[0xFFFF5] = 0x00
mem[0xFFFF6] = 0x00
mem[0xFFFF7] = 0x00

mem[0xB8000] = 08
mem[0xB8001] = 67
mem[0xB8003] = 58
mem[0xB8005] = 92
mem[0xB8007] = 62
mem[0xB8008] = 128
mem[0xB8009] = 95
mem[0xB8055] = 65
mem[0xB80FD] = 65
mem[0xB80FF] = 65
mem[0xB8100] = 65
mem[0xB8101] = 65
mem[0xB8103] = 65
mem[0xB8105] = 65
mem[0xB8107] = 65
mem[0xB8109] = 65
mem[0xB810B] = 65
mem[0xB810D] = 65
mem[0xB810F] = 65
mem[0xB8111] = 65
mem[0xB8113] = 65
mem[0xB8117] = 65
mem[0xB8791] = 65


blink = 1
function disp_vga3()
	term.setCursorPos(1, 1)
	origin = 0xB8000
	
	for i=0, 1936, 2 do
		enc = mem[origin + i]
		word = mem[(origin + i + 1)]
		--color
		if math.floor(enc / 0x10) % 8 == 0 then term.setBackgroundColor(colors.black) end
		if math.floor(enc / 0x10) % 8 == 1 then term.setBackgroundColor(colors.blue) end
		if math.floor(enc / 0x10) % 8 == 2 then term.setBackgroundColor(colors.green) end
		if math.floor(enc / 0x10) % 8 == 3 then term.setBackgroundColor(colors.cyan) end
		if math.floor(enc / 0x10) % 8 == 4 then term.setBackgroundColor(colors.red) end
		if math.floor(enc / 0x10) % 8 == 5 then term.setBackgroundColor(colors.magenta) end
		if math.floor(enc / 0x10) % 8 == 6 then term.setBackgroundColor(colors.brown) end
		if math.floor(enc / 0x10) % 8 == 7 then term.setBackgroundColor(colors.lightGray) end
		if math.floor(enc / 0x10) % 8 == 8 then term.setBackgroundColor(colors.gray) end
		if math.floor(enc / 0x10) % 8 == 9 then term.setBackgroundColor(colors.lightBlue) end
		if math.floor(enc / 0x10) % 8 == 10 then term.setBackgroundColor(colors.lime) end
		if math.floor(enc / 0x10) % 8 == 11 then term.setBackgroundColor(colors.lightBlue) end
		if math.floor(enc / 0x10) % 8 == 12 then term.setBackgroundColor(colors.red) end
		if math.floor(enc / 0x10) % 8 == 13 then term.setBackgroundColor(colors.pink) end
		if math.floor(enc / 0x10) % 8 == 14 then term.setBackgroundColor(colors.yellow) end
		if math.floor(enc / 0x10) % 8 == 15 then term.setBackgroundColor(colors.white) end
		
		if math.floor(enc / 128) == 1 then
			if blink < 32 and blink > 16 then
				io.write(" ")
			else
				io.write(string.char(word))
			end
		else
			io.write(string.char(word))
		end
		
	end
	if blink > 32 then
		blink = 1
		os.queueEvent("fakeEvent")
		os.pullEvent()
	else
		blink = blink + 1
	end
	term.setCursorPos(1,1)
end

--regs16[CX] = 0x0000
while true do
	addr = (segs[CS] * 4) + ip
	decode_inst(mem[addr])
	disp_vga3()
	inc_ip()
end


dump_mem()
print_regs()
