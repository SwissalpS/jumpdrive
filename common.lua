
local has_vacuum_mod = minetest.get_modpath("vacuum")
local has_travelnet_mod = minetest.get_modpath("travelnet")
local has_technic_mod = minetest.get_modpath("technic")
local has_elevator_mod = minetest.get_modpath("elevator")
local has_locator_mod = minetest.get_modpath("locator")

-- add a position offset
local add_pos = function(pos1, pos2)
	return {x=pos1.x+pos2.x, y=pos1.y+pos2.y, z=pos1.z+pos2.z}
end

-- subtract a position offset
local sub_pos = function(pos1, pos2)
	return {x=pos1.x-pos2.x, y=pos1.y-pos2.y, z=pos1.z-pos2.z}
end

-- calculates the power requirements for a jump
local calculate_power = function(radius, distance)
	-- max-radius == 20
	-- distance example: 500

	return 10 * distance * radius
end



-- get pos object from pos
jumpdrive.get_meta_pos = function(pos)
	local meta = minetest.get_meta(pos);
	return {x=meta:get_int("x"), y=meta:get_int("y"), z=meta:get_int("z")}
end

-- set pos object from pos
jumpdrive.set_meta_pos = function(pos, target)
	local meta = minetest.get_meta(pos);
	meta:set_int("x", target.x)
	meta:set_int("y", target.y)
	meta:set_int("z", target.z)
end

local get_target_pos = function(meta)
	return {x=meta:get_int("x"), y=meta:get_int("y"), z=meta:get_int("z")}
end

local get_minus_pos = function(meta)
	return {x=meta:get_int("xminus"), y=meta:get_int("yminus"), z=meta:get_int("zminus")}
end

local get_plus_pos = function(meta)
	return {x=meta:get_int("xplus"), y=meta:get_int("yplus"), z=meta:get_int("zplus")}
end

-- get pos1
local get_pos1 = function(pos)
	local meta = minetest.get_meta(pos);
	return vector.subtract(pos, get_minus_pos(meta))
end

-- get pos2
local get_pos2 = function(pos)
	local meta = minetest.get_meta(pos);
	return vector.add(pos, get_plus_pos(meta))
end

-- get target pos1
local get_target_pos1 = function(pos)
	local meta = minetest.get_meta(pos);
	return vector.subtract(get_target_pos(meta), get_minus_pos(meta))
end

-- get target pos2
local get_target_pos2 = function(pos)
	local meta = minetest.get_meta(pos);
	return vector.add(get_target_pos(meta), get_minus_pos(meta))
end

-- checks if an area is protected
local is_area_protected = function(pos1, pos2, playername)

	if minetest.is_area_protected ~= nil then
		return minetest.is_area_protected(pos1, pos2, playername)
	else
		local protected = false
		for x=pos1.x,pos2.x do
			for y=pos1.y,pos2.y do
				for z=pos1.z,pos2.z do
					local ipos = {x=x, y=y, z=z}
					if minetest.is_protected(ipos, playername) then
						return true
					end
				end
			end
		end
	end

	return false --no protection found
end


jumpdrive.simulate_jump = function(pos)
	local meta = minetest.get_meta(pos)
	local targetPos = jumpdrive.get_meta_pos(pos)

	-- TODO: marker
	-- jumpdrive.show_marker(targetPos, radius, "red")
	-- jumpdrive.show_marker(pos, radius, "green")
end

-- preflight check, for overriding
jumpdrive.preflight_check = function(source, destination, player)
	-- TODO: params pos1/pos2
	return { success=true }
end

-- flight check
jumpdrive.flight_check = function(pos, player)

	local result = { success=true }
	local meta = minetest.get_meta(pos)
	local targetPos = get_target_pos(meta)

	local preflight_result = jumpdrive.preflight_check(pos, targetPos, player)

	if not preflight_result.success then
		-- check failed in customization
		return preflight_result
	end

	local playername = meta:get_string("owner")

	if player ~= nil then
		playername = player:get_player_name()
	end

	local source_pos1 = get_pos1(pos)
	local source_pos2 = get_pos2(pos)

	local target_pos1 = get_target_pos1(pos)
	local target_pos2 = get_target_pos2(pos)

	local distance = vector.distance(pos, targetPos)

	local diameter = vector.distance(source_pos1, source_pos2)
	local radius = diameter / 2
	-- TODO: proper calc
	local power_requirements = calculate_power(radius, distance)

	minetest.log("action", "[jumpdrive] power requirements: " .. power_requirements)

	-- preload chunk
	-- TODO: falls away with emerge code
	-- minetest.get_voxel_manip():read_from_map(pos1, pos2)

	-- check source for protection
	if is_area_protected(source_pos1, source_pos2, playername) then
		return {success=false, pos=pos, message="Jump-source is protected"}
	end

	-- check destination for protection
	if is_area_protected(target_pos1, target_pos2, playername) then
		return {success=false, pos=pos, message="Jump-target is protected"}
	end

	-- skip fuel calc, if creative
	if minetest.check_player_privs(playername, {creative = true}) then
		return result
	end

	local powerstorage = meta:get_int("powerstorage")

	if powerstorage < power_requirements then
		-- not enough power, use items

		-- check inventory
		local inv = meta:get_inventory()
		local power_item = jumpdrive.config.power_item
		local power_item_count = math.ceil(power_requirements / jumpdrive.config.power_item_value)

		if not inv:contains_item("main", {name=power_item, count=power_item_count}) then
			local msg = "Not enough fuel for jump, expected " .. power_item_count .. " " .. power_item

			if has_technic_mod then
				msg = msg .. " or " .. power_requirements .. " EU"
			end

			return {success=false, pos=pos, message=msg}
		end

		-- use crystals
		inv:remove_item("main", {name=power_item, count=power_item_count})
	else
		-- remove power
		meta:set_int("powerstorage", powerstorage - power_requirements)
	end


	return result
end


-- execute whole jump
jumpdrive.execute_jump = function(pos, player)

	local meta = minetest.get_meta(pos)
	local playername = meta:get_string("owner")

	if player ~= nil then
		playername = player:get_player_name()
	end

	local preflight = jumpdrive.flight_check(pos, player)
	if not preflight.success then
		minetest.chat_send_player(playername, preflight.message)
		return false
	end

	local target_pos1 = get_target_pos1(pos)
	local target_pos2 = get_target_pos2(pos)

	-- defer jumping until mapblock loaded
	minetest.emerge_area(target_pos1, target_pos2, function(blockpos, action, calls_remaining, param)
		if calls_remaining == 0 then
			jumpdrive.execute_jump_stage2(pos, player)
		end
	end);
end

-- jump stage 2, after target emerge
jumpdrive.execute_jump_stage2 = function(pos, player)
	
	local meta = minetest.get_meta(pos)
	local targetPos = get_target_pos(meta)
	local offsetPos = vector.subtract(targetPos, pos)

	local source_pos1 = get_pos1(pos)
	local source_pos2 = get_pos2(pos)

	local target_pos1 = get_target_pos1(pos)
	local target_pos2 = get_target_pos2(pos)


	local diameter = vector.distance(target_pos1, target_pos2)
	local radius = diameter / 2

	minetest.log("action", "[jumpdrive] jumping: " ..
		" Source-pos1=" .. minetest.pos_to_string(source_pos1) ..
		" Source-pos2=" .. minetest.pos_to_string(source_pos2) ..
		" Target-pos1=" .. minetest.pos_to_string(target_pos1) ..
		" Target-pos2=" .. minetest.pos_to_string(target_pos2))

	local all_objects = minetest.get_objects_inside_radius(pos, radius * 1.5);

	-- move blocks

	local move_block = function(from, to)
		local node = minetest.get_node(from)
		local newNode = minetest.get_node(to)

		if node.name == "air" and newNode.name == "air" then
			-- source is air and target is air, skip block
			return
		end

		if has_vacuum_mod and node.name == "air" and newNode.name == "ignore" then
			-- fill air with buffer air
			minetest.set_node(to, {name="vacuum:air"})
			local timer = minetest.get_node_timer(to)
			-- buffer air expires after 10 seconds
			timer:start(10)
			return
		end

		local meta = minetest.get_meta(from):to_table() -- Get metadata of current node
		minetest.set_node(from, {name="air"}) -- perf reason (faster)

		minetest.set_node(to, node) -- Move node to new position
		minetest.get_meta(to):from_table(meta) -- Set metadata of new node


		if has_travelnet_mod and node.name == "travelnet:travelnet" then
			-- rewire travelnet target
			jumpdrive.travelnet_compat(to)
		end

		if has_locator_mod then
			if node.name == "locator:beacon_1" or node.name == "locator:beacon_2" or node.name == "locator:beacon_3" then
				-- rewire beacon
				jumpdrive.locator_compat(from, to)
			end
		end

	end

	local x_start = target_pos2.x
	local x_end = target_pos1.x
	local x_step = -1

	if offsetPos.x < 0 then
		-- backwards, invert step
		x_start = target_pos1.x
		x_end = target_pos2.x
		x_step = 1
	end

	local y_start = target_pos2.y
	local y_end = target_pos1.y
	local y_step = -1

	if offsetPos.y < 0 then
		-- backwards, invert step
		y_start = target_pos1.y
		y_end = target_pos2.y
		y_step = 1
	end

	local z_start = target_pos2.z
	local z_end = target_pos1.z
	local z_step = -1

	if offsetPos.z < 0 then
		-- backwards, invert step
		z_start = target_pos1.z
		z_end = target_pos2.z
		z_step = 1
	end

	for ix=x_start,x_end,x_step do
		for iy=y_start,y_end,y_step do
			for iz=z_start,z_end,z_step do
				local from = {x=ix, y=iy, z=iz}
				local to = vector.add(from, offsetPos)
				move_block(from, to)
			end
		end
	end

	if has_elevator_mod then
		jumpdrive.elevator_compat(target_pos1, target_pos1)
	end

	-- move objects
	for _,obj in ipairs(all_objects) do
		-- TODO: check if between pos1 and pos2
		if obj:get_attach() == nil then
			-- object not attached
			obj:moveto( vector.add(obj:get_pos(), offsetPos) )
		end
	end

	-- show animation in target
	minetest.add_particlespawner({
		amount = 200,
		time = 2,
		minpos = targetPos,
		maxpos = {x=targetPos.x, y=targetPos.y+5, z=targetPos.z},
		minvel = {x = -2, y = -2, z = -2},
		maxvel = {x = 2, y = 2, z = 2},
		minacc = {x = -3, y = -3, z = -3},
		maxacc = {x = 3, y = 3, z = 3},
		minexptime = 0.1,
		maxexptime = 5,
		minsize = 1,
		maxsize = 1,
		texture = "spark.png",
		glow = 5,
	})

	return true
end


jumpdrive.update_formspec = function(meta)
	meta:set_string("formspec", "size[8,10;]" ..
		"field[0,1;2,1;x;X;" .. meta:get_int("x") .. "]" ..
		"field[3,1;2,1;y;Y;" .. meta:get_int("y") .. "]" ..
		"field[6,1;2,1;z;Z;" .. meta:get_int("z") .. "]" ..

		"field[0,2;2,1;xplus;X+;" .. meta:get_int("xplus") .. "]" ..
		"field[3,2;2,1;yplus;Y+;" .. meta:get_int("yplus") .. "]" ..
		"field[6,2;2,1;zplus;Z+;" .. meta:get_int("zplus") .. "]" ..

		"field[0,3;2,1;xminus;X-;" .. meta:get_int("xminus") .. "]" ..
		"field[3,3;2,1;yminus;Y-;" .. meta:get_int("yminus") .. "]" ..
		"field[6,3;2,1;zminus;Z-;" .. meta:get_int("zminus") .. "]" ..

		"button_exit[0,4;2,1;jump;Jump]" ..
		"button_exit[2,4;2,1;show;Show]" ..
		"button_exit[4,4;2,1;save;Save]" ..
		"button[6,4;2,1;reset;Reset]" ..

		"list[context;main;0,5;8,1;]" ..

		"button[0,6;4,1;write_book;Write to book]" ..
		"button[4,6;4,1;read_book;Read from book]" ..

		"list[current_player;main;0,7;8,1;]")
end

jumpdrive.write_to_book = function(pos, sender)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()

	if inv:contains_item("main", {name="default:book", count=1}) then
		local stack = inv:remove_item("main", {name="default:book", count=1})

		local new_stack = ItemStack("default:book_written")
		local stackMeta = new_stack:get_meta()

		local data = {}

		data.owner = sender:get_player_name()
		data.title = "Jumpdrive coordinates"
		data.description = "Jumpdrive coordiates"
		data.text = minetest.serialize(jumpdrive.get_meta_pos(pos))
		data.page = 1
		data.page_max = 1

		new_stack:get_meta():from_table({ fields = data })

		if inv:room_for_item("main", new_stack) then
			-- put written book back
			inv:add_item("main", new_stack)
		else
			-- put back old stack
			inv:add_item("main", stack)
		end

	end

end

jumpdrive.read_from_book = function(pos)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()

	if inv:contains_item("main", {name="default:book_written", count=1}) then
		local stack = inv:remove_item("main", {name="default:book_written", count=1})
		local stackMeta = stack:get_meta()

		local text = stackMeta:get_string("text")
		local data = minetest.deserialize(text)
		
		if data == nil then
			return
		end

		local x = tonumber(data.x)
		local y = tonumber(data.y)
		local z = tonumber(data.z)

		if x == nil or y == nil or z == nil then
			return
		end

		meta:set_int("x", x)
		meta:set_int("y", y)
		meta:set_int("z", z)

		-- update form
		jumpdrive.update_formspec(meta)

		-- put book back
		inv:add_item("main", stack)
	end
end

jumpdrive.reset_coordinates = function(pos)
	local meta = minetest.get_meta(pos)

	meta:set_int("x", pos.x)
	meta:set_int("y", pos.y)
	meta:set_int("z", pos.z)

	-- update form
	jumpdrive.update_formspec(meta)

end
